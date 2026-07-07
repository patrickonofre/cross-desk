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

- ☑ **T32 — DTLSServer: advertise + rotação** ✅ (2026-07-04) (R25, R29 servidor)
  - `init(port:psk:advertiseName:pairing:)` — advertise via `NWListener.Service(_crossdesk._udp, TXT proto=1)`; pareamento: pós-HELLO `beginPairing()` (segredo fixo por tentativa, PAIR_SET re-enviado a 2 s), `completePairing()` no ACK → persiste via `onPaired` + recria listener com PSK do segredo (conexão ativa preservada — incerteza 3 morta). Bind race do rebind coberto (retry 5× c/ 0.4 s, guard por `listenerGeneration`). Teardown cancela pareamento não-ACKado (segredo novo na próxima tentativa).
  - Prova: `TransportLoopbackTests.testPairingRotatesToSecretAndListenerAcceptsOnlySecretAfterwards` — secrets iguais nos 2 lados, sessão sobrevive à rotação, 2º cliente só entra com o segredo.

- ☑ **T33 — DTLSClient: endpoint Bonjour + pareamento + fallback** ✅ (2026-07-04) (R27, R29 cliente, R30)
  - `init(endpoint:psk:fallbackPSK:deviceName:)` + convenience host:port (call sites intactos); PAIR_SET → persiste via `onPairSet` ANTES do ACK (duplicado → re-persiste + re-ACKa); fallback: alterna credencial após handshake timeout sem conexão prévia.
  - Prova: `testClientFallsBackToTokenWhenSecretHandshakeTimesOut` (segredo velho → token → re-rotação) + `testDuplicatePairSetPersistsSameSecretAndDoesNotCrash`.

- ☑ **T34 — ServerBrowser (descoberta no cliente)** ✅ (2026-07-04) (R26, R33 detecção)
  - `Sources/Transport/ServerBrowser.swift` — `NWBrowser(_crossdesk._udp)`, `onUpdate([DiscoveredServer])` (lista completa ordenada), `onPermissionState` (waiting → denied, ready → ok), restart em `.failed`, start/stop idempotentes.
  - Prova: `DiscoveryTests.testAdvertisedServerIsDiscoveredAndConnectable` — advertise+browse+**connect via endpoint `.service`** em loopback PASSOU de verdade (1 s, sem skip) → incerteza 1 morta. Skip automático se mDNS bloqueado no ambiente (UAT cobre).

## Fase C — Sessões + UI + bundle

- ☑ **T35 — Fiação nas sessões** ✅ (2026-07-04) (R29/R30/R31 orquestração)
  - `ServerSession(port:pairingCode:edgeSide:advertiseName:pairing:…)` + `onPaired` repassado do transporte; `ClientSession(endpoint:pairedSecret:pairingToken:…)` (precondition: ≥1 credencial) monta primária/fallback e repassa `onPairSet`. `SessionState` inalterado (UI deriva pareado do config) — estados novos não foram necessários.
  - Prova: 110 testes verdes sem regressão.

- ☑ **T36 — UI: lista, token, pareado/esquecer, fallback manual** ✅ (2026-07-04) (R26, R27, R28 UI, R31, R32, R33 UX)
  - **AppState**: `discoveredServers`/`localNetworkDenied` publicados, browser vive só com papel cliente + sessão parada (`updateBrowsing`), `connect(to:token:)` (segredo NUNCA lidera contra servidor ≠ pareado), `connectManual`, `forgetPairing` (R31 dois lados), `toggleServer`, persistência `onPaired`/`onPairSet`, primeiro token curto no init/regeneração. **MenuBarView**: servidor não-pareado exibe token title2 monospace + copiar/regenerar, pareado = selo + Esquecer, IPs no disclosure; cliente = lista com badge de pareado (conecta direto) / "Parear…" expande campo token, vazio = "Procurando…" + dica de Rede Local (R33), "Conectar por IP…" (R32); footer por papel.
  - Prova: `swift build --product CrossDeskApp` limpo (warning pré-existente só) + make-app.sh ok. Fingerprint saiu do fluxo principal (design §5).

- ☑ **T37 — Bundle: Rede Local no Info.plist** ✅ (2026-07-04) (R33)
  - `NSLocalNetworkUsageDescription` + `NSBonjourServices` (`_crossdesk._udp`) no heredoc; `CFBundleVersion` 9→10.
  - Prova: `plutil -p` mostra as chaves no bundle assinado ("CrossDesk Dev").

## Fase D — Validação

- ☑ **T38 — UAT discovery-pairing (2 macs)** — ✅ 2026-07-07, usuário reportou aceitações 1–8 passando (roteiro `UAT-1.0.md` bloco A), sem bugs.
  - What: aceitações 1–8 do spec.md — visibilidade (≤3 s aparece / ≤10 s some), pareamento ok + token errado, rotação (config dos dois lados + reconexão silenciosa pós-restart), esquecer servidor (fallback R30 na prática), esquecer cliente, Rede Local negada→concedida (incerteza 2), fallback IP, regressão kvm-mvp/input-polish. Registrar rename Bonjour em colisão de nome (incerteza 4) se observado.
  - Done when: resultados por aceitação registrados no STATE.md; incertezas 1–4 do design respondidas; sobras viram pendências no STATE.
  - Requer: 2 macs na mesma LAN, TCC concedido, uma rede com mDNS ok (e, se possível, teste com mDNS bloqueado p/ aceitação 7).

## Ordem de execução sugerida

T29+T30+T31 `[P]` → T32 → T33+T34 `[P]` → T35 → T36 (+T37 `[P]` a qualquer momento) → T38

## Rastreabilidade requisito → task

R25→T32 · R26→T34,T36 · R27→T33,T34,T36 · R28→T29,T36 · R29→T30,T31,T32,T33,T35 · R30→T33,T35,T36 · R31→T31,T35,T36 · R32→T36 · R33→T34,T36,T37,T38 · R34→T30
