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
- ◐ **T15 — Integração mac↔mac + latência + UAT** (R14, aceitação 1–5) — **EM ANDAMENTO**
  - ✅ 2026-07-03 17:12: primeira conexão real mac↔mac (beta.6) + travessia de borda REMOTE⇄LOCAL funcionando (provado por log). Spike T2 implicitamente validado: injeção a partir da queue de transporte funcionou.
  - Jornada (betas 1–6): TCC podre por assinatura ad-hoc → cert estável; app "fechando" = quit do macOS na concessão + corrida no relaunch; conexão falhando = código de pareamento divergente → normalização + fingerprint visual.
  - Pendente: aceitação 2 (digitação/modificadores), 4 (Esc 3× com rede cortada), 5 (Wireshark), latência p95 (R14).
  - Requer: usuário conceder TCC nas duas máquinas, segunda máquina mac, Wireshark p/ aceitação 5.
  - Spike T2 (CGEventPost fora da main thread + Esc em REMOTE) valida aqui na prática.

## Fase E — Correções pós-primeira-conexão

- ☑ **T16 — Geometria independente por máquina** ✅ (2026-07-03) (R3, R6, R8)
  - Problema (achado no UAT do T15): cursor "se perdia" — o servidor simulava a posição remota (`VirtualCursor`) escalando deltas pela tela DO SERVIDOR, enquanto o cliente movia em px reais da tela DELE. Resoluções diferentes = duas contabilidades divergentes → borda de retorno disparava cedo/tarde/nunca. Cliente ainda clampava só na tela principal.
  - Cura: cada máquina dona da própria topologia (protocolo §5). `ENTER` ganha `edge u8`; nova msg `LEAVE_REQUEST` (0x12, C→S); cliente detecta a própria borda de retorno via `ScreenTopology` (novo, geometria pura: entrada normalizada→ponto, contenção multi-monitor com slide, saída só por borda externa); `VirtualCursor` removido do servidor (fim do drift estrutural). LEAVE_REQUEST re-enviado a cada movimento "para fora" na borda = retry natural contra perda UDP; servidor idempotente.
  - Bônus: multi-monitor no cliente saiu do "fora de escopo" — contenção cobre todos os monitores.
  - Prova: 63 testes (14 novos `ScreenTopologyTests`, golden vectors regenerados), build da app OK.

- ☑ **T17 — Ícone da menubar sumindo com app vivo** ✅ (2026-07-03)
  - Causa raiz: `MenuBarExtra` é a única UI (LSUIElement); macOS permite arrastar o status item pra fora da barra e **persiste** a remoção (`NSStatusItem Visible Item-0 = false` nos defaults) → ícone some com o processo vivo e não volta nem relançando.
  - Cura: `MenuBarExtra(isInserted:)` pinado (binding rebate remoção em sessão, com log) + heal no launch (flag persistido `false` → `true` antes da cena materializar — cura instalações já afetadas).
  - Se voltar a sumir com a beta.8+: é overflow da menubar (notch/barra cheia — sistema esconde, código não alcança); conferir com `log show --predicate 'subsystem == "dev.crossdesk.mac"' | grep menubar`.

- ☑ **T18 — Trava da seta na máquina sem foco (R16)** ✅ (2026-07-03)
  - Cliente conectado sem foco: trackpad/mouse local movia a seta livremente (seta "fantasma" vagando). Servidor em REMOTE já travava (dissociação + supressão do tap).
  - Cura simétrica no cliente: `connected` → `CGAssociateMouseAndMouseCursorPosition(0)` (mouse físico morto, teclado livre); `ENTER` → reassocia (injeção dirige — evita incerteza dissociação×`CGEventPost`); `LEAVE` → `parkPoint` warpa seta p/ borda de retorno + trava de novo; desconexão/stop → destrava incondicional (espelho do unsuppress do servidor; pior caso heartbeat 6 s).
  - Escapes com cliente travado: cruzar borda pelo servidor, parar servidor, cortar rede, teclado do cliente.
  - Esconder a seta (vs. travar) continua pendência pós-MVP (APIs privadas).

## Ordem de execução sugerida

T1+T2 (paralelo) → T3 → T4+T6+T7+T8+T9 (paralelo) → T5 → T10 → T11+T12 → T13 → T14 → T15 → T16 (surgiu do UAT do T15)
