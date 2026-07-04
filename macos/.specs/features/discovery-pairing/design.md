# Design — discovery-pairing

Referências: [spec.md](spec.md) · [context.md](context.md) · [PROTOCOL.md](../../../../.specs/protocol/PROTOCOL.md) · pares maduros: Deskflow (Zeroconf/mDNS) e lan-mouse (mdns-sd) usam exatamente este padrão de descoberta.

## Visão geral

Tudo em Network.framework nativo — zero dependências novas:

```
SERVIDOR                                      CLIENTE
NWListener (DTLS-PSK, já existe)              NWBrowser("_crossdesk._udp")  ← novo
  + .service("_crossdesk._udp")  ← 1 linha      → lista [nome, endpoint]
                                                NWConnection(endpoint Bonjour, DTLS-PSK)
                                                  ← DTLSClient refatorado p/ NWEndpoint
```

Pareamento continua 100% DTLS-PSK (PROTOCOL.md §1). O que muda é a **origem** da PSK ao longo do ciclo de vida:

```
não-pareado:  PSK = HKDF(token curto)     ← token exibido no servidor, digitado no cliente
pareado:      PSK = HKDF(segredo 128-bit) ← entregue via PAIR_SET dentro do túnel
```

## 1. Descoberta

### Servidor (R25)

`DTLSServer` ganha parâmetro opcional `advertise: (name: String, txt: [String: String])?`. Antes do `listener.start()`:

```swift
listener.service = NWListener.Service(name: name, type: "_crossdesk._udp", txtRecord: NWTXTRecord(["proto": "1"]))
```

Anúncio vive e morre com o listener (cancel → some da rede). Nome da instância = `config.deviceName`. TXT carrega só `proto` — nada sensível (R25). Colisão de nome: Bonjour renomeia sozinho ("Mac (2)") — aceito.

### Cliente (R26) — `ServerBrowser` (novo, `Sources/Transport/ServerBrowser.swift`)

Wrapper de `NWBrowser(for: .bonjour(type: "_crossdesk._udp", domain: nil), using: NWParameters())`:

- `onUpdate: ([DiscoveredServer]) -> Void` — lista completa a cada `browseResultsChangedHandler` (diff é problema da UI/SwiftUI).
- `DiscoveredServer { name: String, endpoint: NWEndpoint }` — endpoint é o `.service(...)` do result, passado direto ao connect (resolução SRV/porta fica com o Network.framework — R27).
- `start()/stop()` idempotentes; estado confinado a queue própria (mesmo padrão DTLSServer/@unchecked Sendable).
- Estado `.waiting(error)` do browser (permissão Rede Local negada aparece aqui como `dns(-65570)`/`.waiting`) → `onUpdate([])` + flag `permissionDenied` para a UI mostrar a dica (R33).

### Ciclo de vida do browse

Browse ativo somente com: papel = cliente E sessão parada E painel aberto ao menos uma vez (start no `onAppear`/mudança de papel; stop ao iniciar sessão ou trocar papel). Menos radiação de queries mDNS e menos prompt de TCC fora de contexto.

## 2. Pareamento e rotação (R28–R31)

### Token (R28) — `PairingKey` estendido

- `generateShortToken() -> String` — 8 chars do alfabeto Crockford-like sem ambíguos (`23456789ABCDEFGHJKMNPQRSTVWXYZ`), via `SecRandomCopyBytes`, retornado como `XXXX-XXXX`.
- `normalize(_:)` (público, extraído do atual inline): remove tudo que não é alfanumérico + lowercase. `psk(fromCode:)` passa a usá-lo — `abcd-efgh` ≡ `ABCDEFGH`. Código longo existente continua funcionando pela mesma rota (compat).
- Fingerprint continua disponível (debug/log), mas sai do fluxo de UI principal — o match agora é o próprio token na tela.

### Mensagens novas (R29, R34) — `Message`

| type | Nome | Direção | Payload |
|------|------|---------|---------|
| 0x05 | PAIR_SET | S→C | `code_len u8` · `code utf8` — segredo novo (32 hex chars = 128 bits) |
| 0x06 | PAIR_ACK | C→S | vazio |

Trafegam **somente dentro do túnel DTLS** já estabelecido. `proto_version` inalterado (=1): decoder antigo ignora tipo desconhecido (§2) → cliente antigo nunca ACKa → servidor fica em modo token para sempre (funcional; documentado no changelog).

### Máquina de estados da rotação

```
SERVIDOR (não-pareado, listener PSK = HKDF(token)):
  conexão + HELLO ok
    → gera segredo S (PairingKey.generateCode(), 128 bits)
    → envia PAIR_SET(S); re-envia a cada 2 s até PAIR_ACK   [idempotente: sempre o MESMO S]
  PAIR_ACK recebido
    → persiste S (callback onPaired(S) → AppState/config)
    → rotateListener(HKDF(S)): cancela listener, recria com PSK nova
      [conexão atual NÃO cai — chaves DTLS da sessão já foram derivadas; listener e connection são independentes]
    → para de exibir token na UI

CLIENTE:
  PAIR_SET(S) recebido
    → persiste S (callback onPairSet(S) → config), responde PAIR_ACK
    → PAIR_SET duplicado (retry do servidor): re-persiste (mesmo valor) + re-ACKa — idempotente
```

**Análise de falha (UDP lossy + quedas no meio):**

| Cenário | Estado resultante | Recuperação |
|---|---|---|
| PAIR_SET perdido | servidor re-envia a cada 2 s | automática |
| Sessão cai antes de PAIR_SET chegar | ambos ainda no token | reconecta com token; rotação recomeça |
| PAIR_ACK perdido, sessão cai | cliente tem S, servidor tem token | cliente tenta S → timeout → fallback token (R30) → conecta → servidor gera S' novo e roda a rotação de novo; cliente sobrescreve S por S' |
| Ambos persistiram | pareado | reconexão silenciosa com S |

Regra de ouro: **servidor só persiste/rotaciona no ACK; cliente persiste no SET; cliente guarda o token digitado até um handshake com segredo funcionar** — cobre todas as janelas.

### Fallback do cliente (R30)

`ClientSession` recebe `credentials: (secret: String?, token: String?)`. Ordem de tentativa por ciclo de conexão: segredo se existir; `handshake timeout` com segredo E token disponível → próxima tentativa (backoff existente) usa token. Sucesso com token → rotação acontece → volta a preferir o segredo novo. Sem credencial válida → estado de erro pedindo token (UI).

### Esquecer (R31)

- Servidor: zera `pairedSecret`, gera token novo, `rotateListener(HKDF(token))` se rodando (ou aplica no próximo start).
- Cliente: zera `pairedSecret` + `pairingCode` + identificação do servidor pareado; volta à lista.

## 3. Config (`AppConfig`)

Campos novos (decode tolerante, padrão já estabelecido):

```swift
/// Segredo pós-rotação (32 hex). "" = não-pareado. JSON por ora (Keychain = pendência existente).
public var pairedSecret: String = ""
/// Nome Bonjour do servidor pareado (cliente) — para destacar na lista e reconectar.
public var pairedServerName: String = ""
```

Semântica por papel:
- **Servidor:** `pairingCode` = token curto atual (regenerado quando não-pareado); `pairedSecret` = segredo pós-ACK.
- **Cliente:** `pairingCode` = último token digitado (mantido para fallback R30); `pairedSecret` = segredo recebido; `serverHost` segue existindo só para o caminho manual (R32).

Migração: config existente com `pairingCode` de 32 hex continua válida — servidor pareado "à moda antiga" segue conectável pelo caminho manual; ao regenerar, nasce token curto.

## 4. Transporte — mudanças pontuais

- **`DTLSServer`:** `init(port:psk:advertise:)`; `rotateListener(psk:)` (cancela+recria listener na mesma queue, conexão ativa preservada); modo pareamento: `startPairing(secret:)` interno pós-HELLO quando iniciado com PSK de token + `onPaired: (String) -> Void`. Timer de re-envio PAIR_SET na queue existente.
- **`DTLSClient`:** `init(endpoint: NWEndpoint, psk:deviceName:)` — `NWEndpoint.service(...)` (descoberta) ou `.hostPort(...)` (manual). Handling de PAIR_SET no `handleDatagram` + `onPairSet: (String) -> Void`. Troca de PSK entre tentativas (fallback R30) = recriar `NWConnection` com parâmetros novos — já é o que `connect()` faz a cada ciclo.
- **`ServerSession`/`ClientSession`:** só fiação — expõem callbacks de pareamento e novos estados para o `AppState` (`.pairing`, `.paired(name)`).

## 5. UI (MenuBarView + AppState)

**Servidor:**
- Não-pareado: token `XXXX-XXXX` grande (title2 monospaced), "Aguardando pareamento…" quando rodando; botão regenerar (só parado ou não-pareado).
- Pareado: "Pareado ✓" + botão "Esquecer pareamento". Token some. Seção de endereços IP: rebaixada para dentro do disclosure manual (descoberta é o caminho principal).

**Cliente:**
- Lista de servidores descobertos (nome + ícone status). Servidor pareado destacado ("já pareado") → clique conecta direto. Não-pareado → clique expande campo token (`XXXX-XXXX`, autoformatação opcional) + botão "Parear e conectar".
- Vazio: "Procurando servidores…" + (se `permissionDenied`) dica Rede Local (R33).
- `DisclosureGroup("Conectar por IP…")`: host + token — caminho manual completo (R32).
- Esquecer pareamento disponível quando pareado.

**AppState:** guarda `discoveredServers: [DiscoveredServer]`, inicia/para `ServerBrowser` conforme papel/sessão, persiste callbacks de pareamento (`onPaired`/`onPairSet` → `saveConfig`).

## 6. Bundle (R33) — `make-app.sh`

Info.plist ganha:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>O CrossDesk usa a rede local para encontrar e conectar suas máquinas.</string>
<key>NSBonjourServices</key>
<array><string>_crossdesk._udp</string></array>
```

Bump `CFBundleVersion`. App não-sandbox: sem entitlements novos; o prompt de Rede Local dispara no primeiro browse/advertise.

## 7. PROTOCOL.md (R34)

- §1: nota de segurança reescrita — token curto (~40 bits) válido só na janela de pareamento; rotação obrigatória para segredo ≥128 bits via PAIR_SET/PAIR_ACK; brute-force offline do handshake de pareamento documentado como limitação até PAKE.
- §3: linhas 0x05/0x06.
- **§7 Discovery (novo):** tipo `_crossdesk._udp`, instância = nome do dispositivo, TXT `proto`, porta via SRV; anúncio obrigatório enquanto servidor ativo; cliente NÃO deve confiar em dados do TXT para segurança (só conveniência).
- Changelog + golden vectors `pair_set`/`pair_ack` em `vectors/v0_1.txt`.

## Incertezas (e onde morrem)

1. **`NWConnection` para endpoint `.service` com parâmetros DTLS** — API pública suporta endpoint Bonjour em qualquer connection; resolução SRV é interna. Risco baixo; provado no teste de loopback do T34 (advertise + browse + connect na mesma máquina). Plano B: resolver manualmente (browse result → `NWEndpoint.hostPort`) — 20 linhas.
2. **Prompt de Rede Local em app não-sandbox assinada self-signed** — comportamento do TCC em macOS 14/15 para apps fora da App Store é o mesmo (prompt automático no primeiro uso de mDNS). Verificado de fato no UAT (T38, aceitação 6). Se o prompt não aparecer e o browse falhar silencioso: dica na UI já cobre; pior caso, caminho manual (R32) segue vivo.
3. **`rotateListener` sem derrubar a conexão ativa** — listener e connection são objetos independentes no Network.framework (cancel de listener não afeta conexões aceitas). Provado no teste de rotação e2e do T32/T33 (loopback).
4. **Colisão de nome Bonjour / rename automático** — comportamento padrão do mDNSResponder; cosmético. Observar no UAT.
