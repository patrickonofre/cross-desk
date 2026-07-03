# Tasks — kvm-mvp

Toolchain verificado: Xcode 26.6, Swift 6.3 (strict concurrency — tipos compartilhados entre queues precisam ser `Sendable`), host macOS 26.5.

Gate padrão: `cd macos/CrossDeskKit && swift test` verde + build da app sem warnings novos.
`[P]` = paralelizável. Status: ☐ pendente · ◐ em progresso · ☑ feito.

## Fase A — Spikes (matam as incertezas do design)

- ☑ **T1 — Spike DTLS** ✅ SUCESSO (2026-07-03)
  - Resultado: DTLS-PSK round-trip OK em localhost, primeira tentativa. Cipher `TLS_PSK_WITH_AES_128_GCM_SHA256`, DTLS 1.2 pinado.
  - Consequência: auth vira código de pareamento→HKDF→PSK (sem certs). PROTOCOL.md §1, spec R9/R11, design e STATE atualizados.
  - Prova: `macos/spikes/dtls-spike/` (`swift run`).

- ☐ **T2 — Spike CGEventPost/threading + Esc-em-REMOTE** `[P com T1]`
  - What: executável que posta eventos de mouse/teclado de uma queue de fundo; validar recepção de Esc por tap com supressão ativa.
  - Where: `macos/spikes/inject-spike/`
  - Done when: comportamento documentado em design.md (incertezas 2 e 3 resolvidas). Requer TCC concedido pelo usuário.

## Fase B — Núcleo puro (sem TCC, 100% testável)

- ☑ **T3 — Package CrossDeskKit + esqueleto** ✅ (módulo único `CrossDeskKit` com pastas por área — mais simples que multi-target, mesma organização do design)

- ☑ **T4 — Protocol: Message encode/decode** ✅ (R5, R15) — `Sources/Protocol/Message.swift`; decode tolerante a tipo desconhecido; testes round-trip + truncado/malformado/UTF-8 inválido.

- ☑ **T5 — Golden vectors** ✅ (R15) — `.specs/protocol/vectors/v0_1.txt` (10 mensagens + datagrama composto), todos provados por `MessageTests`.

- ☑ **T6 — HIDKeycodes** ✅ (R5, R6) — 116 entradas bidirecionais; consumer keys (volume/Fn) fora por design; testes de identidade e modificadores.

- ☑ **T7 — EdgeDetector + VirtualCursor** ✅ (R2, R3) — geometria pura, multi-monitor (borda interna não dispara), retorno normalizado; 12 testes.

- ☑ **T8 — PressedKeys** ✅ (R7) — não-modificadores soltos antes de modificadores no drain.

- ☑ **T9 — ConfigStore JSON** ✅ (R13) — defaults em arquivo ausente; corrupto lança erro (não descarta pairing code silenciosamente).

Gate Fase B: **39 testes, 0 falhas** (`swift test`, 2026-07-03).

## Fase C — Integração com o sistema (precisa TCC/hardware)

- ☑ **T10 — Transport: DTLSServer/DTLSClient** ✅ (R9, R10)
  - PSK no lugar de Identity/TOFU (decisão pós-T1). Reconexão com backoff 1→30 s, HEARTBEAT 2 s/timeout 6 s, handshake timeout 5 s (bug achado pelo teste de reconexão: conexão presa em `.preparing` nunca falha sozinha), split de datagramas ≤1200 B.
  - 5 testes loopback com DTLS real (handshake, mensagens, PSK errada rejeitada, reconexão pós-restart do servidor, split).

- ☑ **T11 — InputCapture (tap) + EmergencyEscape** ✅ código (R1, R4) — runtime pende TCC (T15). flagsChanged→key up/down de modificadores; re-enable em `tapDisabledByTimeout`; Esc 3×/1 s puro e testado.
- ☑ **T12 — InputInjector** ✅ código (R6, R7) — clique duplo via `mouseEventClickState`, flags de modificadores em todo evento, drag conforme botões, resto fracionário de scroll. Runtime pende TCC (T15).
- ☑ **T13 — ServerSession + ClientSession** ✅ código — state machine LOCAL⇄REMOTE, cursor dissociado em REMOTE, warp de volta na borda de retorno, unsuppress incondicional em desconexão.

## Fase D — App

- ☑ **T14 — App menubar** ✅ (R11, R12, R13)
  - **SPEC_DEVIATION:** casca Xcode (.xcodeproj) → executável SPM (`App/`) + `Scripts/make-app.sh` que monta `macos/build/CrossDesk.app` (Info.plist com `LSUIElement`, assinatura ad-hoc). Motivo: 100% scriptável, sem pbxproj à mão. Xcode abre o `Package.swift` normalmente.
  - Assinatura ad-hoc (zero identidades na máquina) → macOS pode re-pedir TCC após rebuild. Cert real quando houver conta Apple Developer.
- ☐ **T15 — Integração mac↔mac + latência + UAT** (R14, aceitação 1–5) — **próximo; interativo**
  - Requer: usuário conceder TCC nas duas máquinas, segunda máquina mac, Wireshark p/ aceitação 5.
  - Spike T2 (CGEventPost fora da main thread + Esc em REMOTE) valida aqui na prática.

## Ordem de execução sugerida

T1+T2 (paralelo) → T3 → T4+T6+T7+T8+T9 (paralelo) → T5 → T10 → T11+T12 → T13 → T14 → T15
