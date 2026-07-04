# Spec — discovery-pairing (servidor visível na LAN + pareamento por token curto)

**Escopo:** Large (transporte, protocolo, config, UI dos dois papéis). Pipeline: spec → design → tasks → execute.

**Contexto:** hoje a conexão é 100% manual: o usuário lê IP/hostname no servidor, digita no cliente e copia um código de pareamento de 32 hex chars. O roadmap (Fase 4 raiz) já previa "discovery mDNS + pareamento com código curto" — esta feature puxa isso para a app macOS agora. Fluxo-alvo do usuário: ligo o servidor → ele fica visível na rede; ligo o cliente → vejo o servidor numa lista; peço para conectar → digito um token curto que está aparecendo na tela do servidor; conectado com segurança.

## Objetivo

Cliente encontra o servidor sozinho (zero IP/porta digitados) e o pareamento exige apenas um token curto legível exibido no servidor. Depois do primeiro pareamento, reconexões são automáticas e silenciosas. Segurança preservada: todo tráfego continua DTLS-PSK; o token curto vale só para a janela de pareamento e é substituído por segredo forte de 128 bits rotacionado dentro do túnel criptografado.

## Requisitos

### Grupo A — Descoberta

- **R25 — Servidor anunciado via Bonjour.** Enquanto o papel servidor está rodando, o `NWListener` anuncia o serviço `_crossdesk._udp` na LAN com o `deviceName` como nome da instância e TXT `proto=<versão>`. Ao parar, o anúncio some. Nenhuma informação sensível (token, fingerprint, segredo) trafega no anúncio.
- **R26 — Cliente lista servidores em tempo real.** Com papel cliente selecionado (e sessão parada), a UI mostra a lista de servidores descobertos (nome da instância), atualizada dinamicamente (aparece/some conforme o servidor liga/desliga).
- **R27 — Conexão sem digitar IP/porta.** Selecionar um servidor da lista conecta via endpoint Bonjour (porta resolvida pelo SRV do serviço). O campo de host manual deixa de ser o caminho principal.

### Grupo B — Pareamento por token curto + rotação

- **R28 — Token curto de pareamento.** Servidor não-pareado exibe token de 8 caracteres (alfabeto sem ambíguos — sem 0/O/1/I/L —, ~40 bits), formatado `XXXX-XXXX`, em fonte grande/monoespaçada. Normalização antes da derivação (remove separadores/espaços, case-insensitive): digitar `abcd-efgh` ou `ABCDEFGH` dá no mesmo. PSK derivada pela mesma rota HKDF existente (`PairingKey.psk(fromCode:)`).
- **R29 — Rotação para segredo forte após o 1º handshake.** Sessão estabelecida com PSK do token → servidor gera segredo de 128 bits (hex), envia `PAIR_SET` (0x05) dentro do túnel DTLS e repete até receber `PAIR_ACK` (0x06) — retry idempotente (mesmo segredo), pois roda sobre UDP. Cliente persiste o segredo ao receber e responde ACK. Servidor persiste ao receber o ACK e passa a aceitar novos handshakes só com o segredo. Reconexões futuras não pedem token (R30).
- **R30 — Reconexão automática com fallback.** Cliente pareado conecta direto com o segredo. Se o handshake com o segredo falhar por timeout E um token tiver sido digitado nesta sessão de pareamento, tenta o token (cobre "servidor esqueceu o pareamento"). Se nada funcionar, UI pede token novo. Servidor não-pareado (pós-esquecer) exibe token novo.
- **R31 — Esquecer pareamento nos dois lados.** Servidor: apaga segredo, regenera token, volta a "aguardando pareamento". Cliente: apaga segredo/token, volta à lista de servidores.
- **R32 — Fallback manual por IP.** Caminho atual (host + token digitados) continua existindo atrás de um disclosure "Conectar por IP…" — para redes que bloqueiam mDNS.

### Grupo C — Sistema e contrato

- **R33 — Permissão Rede Local declarada e tratada.** Info.plist (gerado pelo make-app.sh) ganha `NSLocalNetworkUsageDescription` e `NSBonjourServices` (`_crossdesk._udp`). Permissão negada → lista vazia com dica de como conceder (Ajustes → Privacidade → Rede Local); fallback manual (R32) continua funcional.
- **R34 — Protocolo documentado + golden vectors.** PROTOCOL.md ganha §7 (Discovery: tipo de serviço, TXT, porta via SRV), mensagens 0x05/0x06 na tabela §3, nota de segurança do token curto atualizada no §1, changelog. Golden vectors de PAIR_SET/PAIR_ACK acrescidos. `proto_version` inalterado (=1): tipos novos são ignoráveis por decoders antigos (§2) — cliente antigo simplesmente nunca ACKa e o servidor permanece em modo token (funcional, documentado).

## Segurança (análise explícita)

- **Brute-force online do token:** inviável na prática — servidor aceita 1 conexão por vez (slot único + handshake timeout serializa tentativas) e 40 bits ≫ qualquer taxa alcançável assim.
- **Brute-force offline (sniffer na LAN captura o handshake de pareamento):** 40 bits são quebráveis offline. Janela de exposição = somente o(s) handshake(s) da fase de pareamento (segundos, uma vez na vida do par); o segredo rotacionado de 128 bits nunca é derivável do token. Aceito e documentado no PROTOCOL.md §1; eliminação definitiva = PAKE (SPAKE2), já previsto como upgrade futuro.
- **Segredo em JSON plano:** herda a pendência existente (migração Keychain pós-MVP, já rastreada no STATE.md).

## Fora de escopo

- PAKE (SPAKE2) — Fase 4 do roadmap raiz.
- Múltiplos clientes pareados simultâneos (MVP segue 1 cliente; config guarda 1 pareamento).
- Aprovação manual no servidor ("Fulano quer conectar — permitir?") — o token já é a aprovação.
- Keychain para o segredo (pendência pós-MVP existente).
- Descoberta fora da LAN (mesmo broadcast domain apenas — limitação mDNS).

## Aceitação (UAT)

1. **Visibilidade:** servidor iniciado aparece na lista do cliente em ≤3 s; servidor parado some da lista em ≤10 s.
2. **Pareamento:** token exibido no servidor digitado no cliente → conecta e input flui. Token errado → erro claro no cliente (sem crash, sem travar o slot do servidor indefinidamente).
3. **Rotação:** após 1º pareamento, servidor para de exibir token ("Pareado"); reiniciar a app cliente → reconecta sozinha, sem pedir token. Config dos dois lados contém o segredo.
4. **Esquecer no servidor:** cliente (ainda com segredo velho) tenta reconectar → falha, UI pede token; digitar o token novo re-pareia.
5. **Esquecer no cliente:** volta à lista; conectar de novo exige token atual do servidor.
6. **Rede Local negada:** negar a permissão → lista vazia + dica visível; conceder em Ajustes → lista popula sem reiniciar a app (ou com relaunch guiado, o que a plataforma exigir — registrar comportamento real).
7. **Fallback IP:** com descoberta indisponível, "Conectar por IP…" + token funciona de ponta a ponta.
8. **Regressão:** travessia, digitação, scroll, retorno e escape de emergência (kvm-mvp/input-polish) intactos após pareamento por descoberta.

## Decisões do usuário (context.md)

Token curto + rotação · reconexão automática · fallback manual mantido — registradas em [context.md](context.md).
