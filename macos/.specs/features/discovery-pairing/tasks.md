# Tasks — discovery-pairing

Numeração continua a do projeto (input-polish terminou em T28). Gate padrão: `cd macos/CrossDeskKit && swift test` verde + `Scripts/make-app.sh` sem warnings novos.
`[P]` = paralelizável. Status: ☐ pendente · ◐ em progresso · ☑ feito.

**Pré-requisito:** nenhum spike — incertezas 1 e 3 do design morrem nos testes de loopback (T32–T34); incerteza 2 morre no UAT (T38).

## Fase A — Núcleo puro (testável headless) `[P entre si]`

- ☑ **T29 — Token curto no PairingKey** ✅ (2026-07-04) (R28)
  - `generateShortToken()` — 8 chars, alfabeto sem ambíguos, `XXXX-XXXX`, rejection sampling (sem viés de módulo); `normalize(_:)` público (strip não-alfanuméricos + lowercase) agora usado por `psk(fromCode:)` — hífen/caixa não mudam a PSK; código longo deriva igual a antes (compat).
  - Prova: `PairingKeyTests` (+5) — formato/alfabeto/sem-ambíguos, unicidade (100), equivalência `ABCD-EFGH`≡`abcdefgh`, normalize.

- ☑ **T30 — Mensagens PAIR_SET/PAIR_ACK + protocolo** ✅ (2026-07-04) (R29 fio, R34)
  - `Message.pairSet(code:)` 0x05 (`code_len u8` + utf8, truncado→invalidPayload) e `.pairAck` 0x06; PROTOCOL.md: §1 reescrito (duas fontes de código, análise de brute-force on/offline), tabela §3, **§6 Pareamento** (regras da rotação — persiste-no-ACK/persiste-no-SET, fallback token) e **§7 Descoberta** novos (Versionamento virou §8), changelog; vectors `pair_set`/`pair_ack` em `v0_1.txt`. `InputInjector.apply` cobre os tipos novos (transport-level, break).
  - Prova: `MessageTests` (+2 vectors no golden set, round-trip, truncado).

- ☑ **T31 — Config: campos de pareamento** ✅ (2026-07-04) (R29/R30/R31 persistência)
  - `pairedSecret` + `pairedServerName` no `AppConfig` (default `""`), init + decode tolerante (`decodeIfPresent ?? default`).
  - Prova: `ConfigStoreTests` — JSON de build antigo (sem as chaves) carrega com defaults; round-trip preserva.

## Fase B — Transporte (depende de T29–T31)

- ☐ **T32 — DTLSServer: advertise + rotação** (R25, R29 servidor)
  - What: `init(port:psk:advertise:)` com `NWListener.Service("_crossdesk._udp", TXT proto=1)`; modo pareamento (iniciado com PSK de token): pós-HELLO gera segredo (`PairingKey.generateCode()`), envia `PAIR_SET` com re-envio a cada 2 s até `PAIR_ACK` (mesmo segredo — idempotente); no ACK → `onPaired(secret)` + `rotateListener(psk:)` (cancela+recria listener, conexão ativa preservada).
  - Where: `Sources/Transport/DTLSServer.swift`.
  - Done when: análise de falha do design (tabela §2) coberta: SET perdido re-envia; ACK duplicado inócuo; rotateListener não derruba a sessão ativa (incerteza 3 morta).
  - Prova: `TransportLoopbackTests` — pareamento e2e em loopback (server token-mode + client → PAIR_SET/ACK → callbacks disparam com o mesmo segredo → sessão segue viva → nova conexão só entra com PSK do segredo).

- ☐ **T33 — DTLSClient: endpoint Bonjour + pareamento + fallback** (R27, R29 cliente, R30)
  - What: `init(endpoint: NWEndpoint, psk:deviceName:)` (`.service` ou `.hostPort` — call sites atualizados); `handleDatagram` trata PAIR_SET → `onPairSet(secret)` + PAIR_ACK (duplicado → re-ACK); fallback de credencial: `credentials (secret?, token?)` + troca de PSK no ciclo de reconexão após handshake timeout com segredo.
  - Where: `Sources/Transport/DTLSClient.swift`.
  - Done when: PAIR_SET duplicado re-ACKa sem re-persistir efeito colateral; sequência "segredo falha → token conecta → rotação → segredo novo" funciona.
  - Prova: `TransportLoopbackTests` — fallback e2e (server com PSK X, client com segredo errado + token X → conecta na 2ª tentativa), ACK duplicado.

- ☐ **T34 — ServerBrowser (descoberta no cliente)** (R26, R33 detecção)
  - What: `ServerBrowser` (`NWBrowser` de `_crossdesk._udp`): `onUpdate([DiscoveredServer])` (name + endpoint), `permissionDenied` a partir de `.waiting`, start/stop idempotentes, queue própria.
  - Where: `Sources/Transport/ServerBrowser.swift` (novo).
  - Done when: advertise do T32 na mesma máquina aparece no browse (incerteza 1 morta: connect via endpoint `.service` incluso no teste); stop cessa updates.
  - Prova: `TransportLoopbackTests` (ou `DiscoveryTests` novo) — advertise+browse+connect loopback com timeout generoso (mDNS local).

## Fase C — Sessões + UI + bundle

- ☐ **T35 — Fiação nas sessões** (R29/R30/R31 orquestração)
  - What: `ServerSession` aceita `advertiseName` + repassa `onPaired`; `ClientSession` aceita endpoint/credenciais + repassa `onPairSet`; estados novos para UI (`pairing`, `paired(name)`) no `SessionState` se necessário.
  - Where: `Sources/Server/ServerSession.swift` · `Sources/Client/ClientSession.swift` · `Sources/Protocol/` (SessionState, onde vive hoje).
  - Done when: callbacks chegam ao caller com os dados certos; nenhuma regressão nos testes existentes.
  - Prova: testes existentes verdes + asserts de fiação onde couber (headless).

- ☐ **T36 — UI: lista, token, pareado/esquecer, fallback manual** (R26, R27, R28 UI, R31, R32, R33 UX)
  - What: **Servidor** — token `XXXX-XXXX` grande quando não-pareado, "Pareado ✓" + Esquecer quando pareado, endereços IP movidos pro disclosure. **Cliente** — lista de descobertos (pareado destacado, conecta direto; não-pareado expande campo token), vazio = "Procurando…" + dica Rede Local se negada, `DisclosureGroup("Conectar por IP…")` com host+token, Esquecer. **AppState** — `discoveredServers`, ciclo de vida do browser (papel/sessão), persistência dos callbacks de pareamento.
  - Where: `App/MenuBarView.swift` · `App/AppState.swift`.
  - Done when: fluxos do design §5 completos; build roda; estados visuais coerentes com `sessionState`.
  - Prova: build + inspeção manual (UI); lógica não-visual (ex.: decisão de credencial) coberta por testes de AppState se extraível.

- ☐ **T37 — Bundle: Rede Local no Info.plist** `[P — a qualquer momento]` (R33)
  - What: `NSLocalNetworkUsageDescription` + `NSBonjourServices` (`_crossdesk._udp`) no heredoc do plist; bump `CFBundleVersion`.
  - Where: `Scripts/make-app.sh`.
  - Done when: app buildada contém as chaves (`plutil -p`); prompt de Rede Local dispara no primeiro browse (verificação final no T38).
  - Prova: `plutil -p build/CrossDesk.app/Contents/Info.plist` mostra as chaves.

## Fase D — Validação

- ☐ **T38 — UAT discovery-pairing (2 macs)**
  - What: aceitações 1–8 do spec.md — visibilidade (≤3 s aparece / ≤10 s some), pareamento ok + token errado, rotação (config dos dois lados + reconexão silenciosa pós-restart), esquecer servidor (fallback R30 na prática), esquecer cliente, Rede Local negada→concedida (incerteza 2), fallback IP, regressão kvm-mvp/input-polish. Registrar rename Bonjour em colisão de nome (incerteza 4) se observado.
  - Done when: resultados por aceitação registrados no STATE.md; incertezas 1–4 do design respondidas; sobras viram pendências no STATE.
  - Requer: 2 macs na mesma LAN, TCC concedido, uma rede com mDNS ok (e, se possível, teste com mDNS bloqueado p/ aceitação 7).

## Ordem de execução sugerida

T29+T30+T31 `[P]` → T32 → T33+T34 `[P]` → T35 → T36 (+T37 `[P]` a qualquer momento) → T38

## Rastreabilidade requisito → task

R25→T32 · R26→T34,T36 · R27→T33,T34,T36 · R28→T29,T36 · R29→T30,T31,T32,T33,T35 · R30→T33,T35,T36 · R31→T31,T35,T36 · R32→T36 · R33→T34,T36,T37,T38 · R34→T30
