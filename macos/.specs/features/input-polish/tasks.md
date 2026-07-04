# Tasks — input-polish

Numeração continua a do projeto (kvm-mvp terminou em T18). Gate padrão: `cd macos/CrossDeskKit && swift test` verde + `Scripts/make-app.sh` sem warnings novos.
`[P]` = paralelizável. Status: ☐ pendente · ◐ em progresso · ☑ feito.

**Pré-requisito:** decisão pendente 1 do spec.md (API privada) confirmada pelo usuário antes do T20 — T19 pode rodar antes (é justamente a prova).

## Fase A — Spike (mata a incerteza central)

- ☑ **T19 — Spike ocultação de cursor em macOS 26** ✅ (2026-07-03)
  - Prova: `macos/spikes/conceal-spike/` (`swift run conceal-spike`).
  - Resultado (macOS 27.0 build 26A5368g): (a) `dlsym` resolve os 2 símbolos privados; `CGSSetConnectionProperty`→0, `CGDisplayHideCursor`→0 → **API privada viável, R17 segue com ela**. (b) warp offscreen **CLAMPA** (não sai dos bounds) → warp-offscreen descartado como fallback; fallback do R17 = park-visible. (c) sleep-survival: modo `--sleep-test` guardado (apaga a tela) — deixado pro UAT 1; design não depende (R18/R19 curam qualquer causa).
  - Incertezas 1 e 2 do design fechadas.

## Fase B — Núcleo puro (testável headless) `[P entre si, após T19]`

- ☑ **T20 — CursorConcealer** ✅ (2026-07-03) (R17)
  - `Sources/Cursor/CursorConcealer.swift` — hide/show idempotentes e balanceados contra o contador do sistema, `dlsym` lazy (símbolos privados em `CursorConcealBackend.live`), `isAvailable`, no-op logado quando indisponível, `reassert()` p/ R19. Config `concealCursor` no `AppConfig` (default true) + decode tolerante (config antigo sem o campo não quebra).
  - Prova: `CursorConcealerTests` (5) — balanceado, idempotente, indisponível→no-op, reassert só quando hidden. Efeitos CG injetados por closure.

- ☑ **T21 — CursorSentinel + SentinelPolicy** ✅ (2026-07-03) (R18 cliente)
  - `Sources/Cursor/CursorSentinel.swift` — estado-alvo `.unlocked/.locked(park:)`, watchdog `DispatchSourceTimer` 250 ms, `SentinelPolicy` pura (drift ε=2 px) → re-warp + re-dissocia + `warpsRecovered`. `InputInjector.setLocalCursorLocked` removido; dissociação agora só no sentinel. `ClientSession` orquestra engage/release (release SEMPRE incondicional em disconnect/stop — T18 preservado).
  - Prova: `SentinelPolicyTests` (2) + `CursorSentinelTests` (9) — engage/tick(drift)/recover/release/reassert/idempotência com efeitos mockados e `tick()` determinístico.

- ☑ **T22 — SystemStateObserver** ✅ (2026-07-03) (R19)
  - `Sources/Cursor/SystemStateObserver.swift` — assina `didWake`/`screensDidWake`/`sessionDidBecomeActive` (via `NotificationCenter` injetado; **atenção: workspace center, não `.default`**) + `CGDisplayRegisterReconfigurationCallback` (ignora `.beginConfigurationFlag`); `onReassert(reason:)` com debounce por geração (1 s).
  - Prova: `SystemStateObserverTests` (3) — notificação→callback, rajada→1 callback, stop silencia.

- ☑ **T23 — Mensagem SCROLL_CONTINUOUS 0x23** ✅ (2026-07-03) (R20 fio)
  - `Message.scrollContinuous` + `ScrollPhase`/`MomentumPhase` (enums u8 neutros); encode/decode (fase desconhecida→`.none`, forward-compat); PROTOCOL.md §3 + §5 + changelog; golden vector `scroll_cont` acrescido (`proto_version` inalterado). 
  - Prova: `MessageTests` — vector, round-trip (2 casos), fase desconhecida→none, truncado→throws.

## Fase C — Integração com o sistema

- ☑ **T24 — Servidor: re-warp contínuo + conceal + reassert** ✅ código (2026-07-03) (R17, R18, R19)
  - `ServerSession` — `parkPoint` capturado no cruzamento; `handleRemote(.mouseMoved)` re-warpa a cada move; →REMOTE `concealer.hide()` (atrás de `conceal`) / →LOCAL `concealer.show()`; `reassertRemoteLock()` (via observer) re-suprime + re-dissocia + `capture.reassertEnabled()` + `concealer.reassert()`; métricas por tipo. `InputCapture.reassertEnabled()` novo.
  - Runtime (log warp/reassert, aceitações 1–3) pende T28 (2 macs). Build + 99 testes verdes.

- ☑ **T25 — Cliente: sentinel + conceal + reassert** ✅ código (2026-07-03) (R17, R18, R19)
  - `ClientSession` reescrito: `CursorSentinel` (engage em `connected` no ponto atual / em `LEAVE` no park da borda via `onFocusLost`; release em `ENTER` via `onFocusGained` / disconnect / stop — incondicional); conceal acoplado a onLock/onUnlock (gated por `conceal`); `observer.onReassert`→`sentinel.reassert()`; métricas.
  - Nota: reassert re-aplica o MESMO park (recompute pós-mudança de topologia = refinamento futuro; warp clampa se o park saiu da tela — seguro). Runtime pende T28.
  - Prova (headless): `InputInjectorFocusTests` (3) — onFocusGained/Lost + park na borda.

- ☑ **T26 — Captura e injeção de scroll contínuo + autorepeat + supressão** ✅ código (2026-07-03) (R20, R21, R22)
  - `InputCapture` — branch `isContinuous`→`scrollContinuous` (pixel deltas + fases) vs. discreto→`scroll` (linhas); mapeadores CG↔neutro. `InputInjector` — `postScrollContinuous` (`.pixel` + point deltas + fase/momentum/isContinuous), autorepeat via `PressedKeys.currentlyPressed` (zero bytes no fio), `source.localEventsSuppressionInterval = 0` no init.
  - Prova: `ScrollPhaseMappingTests` (3) — round-trip fase/momentum CG↔neutro, desconhecido→none. Sensação de trackpad/momentum (incerteza 3) pende T28.

- ☑ **T27 — InputMetrics + coalescing condicional** ✅ (2026-07-03) (R23, R24)
  - `Sources/Metrics/InputMetrics.swift` — contadores atômicos por tipo/datagrama/merge/warp/reassert, `logSummary` em `stop()`. `MoveCoalescer.coalesce` (puro) pronto mas **DORMENTE** (não plugado no hot path — decisão: ligar só se T28 mostrar fila>1 em regime).
  - Prova: `InputMetricsTests` (2) + `MoveCoalescerTests` (4) — soma de moves consecutivos, preserva não-moves, identidade/vazio.

## Fase D — Validação

- ◐ **T28 — UAT input-polish + latência p95** — **ÚNICO PENDENTE** (código T19–T27 pronto, 99 testes verdes)
  - What: aceitações 1–8 do spec.md (matriz standby/wake/screensaver/display/Dock, scroll, autorepeat, convivência local, regressão kvm-mvp) + medição p95 captura→injeção (fecha R14 pendente do T15 do kvm-mvp) usando as métricas do T27.
  - Decisões a fechar no UAT:
    - **Coalescing (R23):** `MoveCoalescer` está dormente. Ler `metrics [server] capturedMouseMove=…` no log sob trackpad 90–120 Hz; se houver backlog de envio (fila>1 em regime), plugar no drain do `ServerSession`. Senão, registrar "não necessário".
    - **Sleep-survival (incerteza 4):** rodar `swift run conceal-spike --sleep-test` e registrar se a dissociação cai no wake (esperado: cai → confirma necessidade do R19).
    - **Invisibilidade (UAT 3):** confirmar visualmente que a seta some de fundo (spike só provou os CGError=0).
    - **Momentum sintético (incerteza 3):** ver se Safari/Xcode fazem rubber-band com as fases injetadas.
    - **Reassert-park:** se mudança de topologia durante trava deixar a seta em lugar ruim, implementar recompute do park (hoje re-aplica o mesmo ponto).
  - Done when: resultados por aceitação registrados (spec.md ou STATE); incertezas 3/4/5 do design respondidas no STATE; pendências que sobrarem viram itens no STATE.md.
  - Requer: 2 macs, TCC concedido, `pmset displaysleepnow` para forçar standby.

## Ordem de execução sugerida

T19 → (decisão API privada) → T20+T21+T22+T23 `[P]` → T24+T25 (paralelos entre si) → T26+T27 `[P]` → T28

## Rastreabilidade requisito → task

R17→T19,T20,T24,T25 · R18→T21,T24,T25 · R19→T22,T24,T25 · R20→T23,T26 · R21→T26 · R22→T26 · R23→T27 · R24→T27,T28 · (R14 kvm-mvp)→T28
