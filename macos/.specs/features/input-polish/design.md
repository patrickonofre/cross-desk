# Design — input-polish

## Pesquisa (2026-07-03)

Como os pares resolvem exatamente o problema desta feature:

| Projeto | Ocultação | Trava do cursor | Sleep/wake |
|---|---|---|---|
| **Deskflow** (`OSXScreen.mm`) | `CGSSetConnectionProperty(_CGSDefaultConnection(), _CGSDefaultConnection(), "SetsCursorInBackground", true)` + `CGDisplayHideCursor` | Warp para o **centro** ao sair + re-warp; `CGSetLocalEventsSuppressionInterval(0.0)`; chama `CGAssociateMouseAndMouseCursorPosition(true)` dentro de hide/show (fix de bug "mouse randomly not showing/hiding") | Thread própria com `IORegisterForSystemPower`; evento de resume redispara setup |
| **lan-mouse** (`input-capture/src/macos.rs`) | `CGDisplay::hide_cursor` / `show_cursor` no grab/release | **Re-warp contínuo** a cada `MouseMoved`/`*Dragged` (`reset_cursor()`); não depende de dissociação | `CGDisplayRegisterReconfigurationCallback` para mudança de displays; sem tratamento explícito de sleep |
| **Apple DTS** (forums thread 756199, 2024) | Confirma que `SetsCursorInBackground` funciona, **exceto** quando o Dock é o alvo ativo (lógica especial do WindowServer, intencional, não é questão de privilégio) | Alternativas sugeridas: warp offscreen via `CGWarpMouseCursorPosition`; overlay window acima de `kCGDockWindowLevelKey`; `NSCursor.hide()` repetido por timer | — |

**Conclusões que moldam o design:**

1. **Ninguém confia só na dissociação.** Ambos os projetos maduros usam ocultação + re-warp contínuo. A dissociação do R16 vira reforço, não fonte de verdade — explica a seta andando pós-standby sem precisarmos provar a condição exata de reset (comportamento não documentado pela Apple; flagrado como incerteza, mitigado por design).
2. **A API privada é o único hide global que funciona de fundo** — e é estável há >10 anos (Barrier→Deskflow). Resolver símbolos via `dlsym` (nunca linkar `CGSSetConnectionProperty`/`_CGSDefaultConnection` direto) e tratar ausência como "hide indisponível".
3. **Scroll de trackpad é outra classe de evento**: lan-mouse separa contínuo (`SCROLL_WHEEL_EVENT_POINT_DELTA_AXIS_*`) de discreto (linhas). Hoje capturamos só `fixedPtDelta` (linhas) e injetamos inteiros — trackpad vira scroll "aos trancos" no cliente.
4. **Supressão local de eventos injetados**: default de 250 ms faz o input local brigar com o injetado; Deskflow zera o intervalo. Em Swift moderno: `CGEventSource.localEventsSuppressionInterval` (público).

## Arquitetura

Três componentes novos em `CrossDeskKit`, integrações pontuais nos existentes:

```
Sources/Cursor/                      # novo — compartilhado servidor/cliente
├── CursorConcealer.swift            # R17: hide/show global (dlsym da API privada, fallback no-op)
├── CursorSentinel.swift             # R18: estado-alvo da trava + watchdog (cliente) 
└── SystemStateObserver.swift        # R19: wake/screensaver/sessão/displays → onReassert
```

### CursorConcealer (R17)

- `hide()` / `show()`; internamente: primeira chamada resolve `_CGSDefaultConnection` e `CGSSetConnectionProperty` via `dlsym(RTLD_DEFAULT, ...)`; indisponível → `isAvailable == false`, chamadas viram no-op logado.
- `CGDisplayHideCursor`/`ShowCursor` balanceados (contador do sistema) — `show()` idempotente via estado interno.
- Consumidores: `ServerSession` (hide em →REMOTE, show em →LOCAL) e `CursorSentinel` no cliente (hide ao travar, show ao destravar), atrás da config `concealCursor`.

### CursorSentinel (R18, cliente)

Substitui a chamada crua `setLocalCursorLocked` do `InputInjector` (T18):

```
estado-alvo: .unlocked | .locked(park: CGPoint)
engage(park:)  → warp(park) + dissocia + hide (se config) + inicia watchdog
release()      → para watchdog + reassocia + show   [incondicional, nunca falha]
tick (250 ms)  → location() distante de park > ε (2 px)?
                 → warp(park) + re-dissocia + contador warpsRecovered++
```

- Fonte de posição do watchdog: `CGEvent(source: nil)?.location` (sem TCC novo; polling só enquanto travado — custo desprezível a 4 Hz).
- Lógica de decisão (drift > ε, cálculo de park) em tipo puro testável (`SentinelPolicy`), efeitos (warp/dissocia/timer) injetados por closures — padrão já usado em `EdgeDetector`/`ScreenTopology`.
- `ClientSession` passa a orquestrar: `connected`/`LEAVE` → `engage(park:)`; `ENTER` → `release()`; `disconnected`/`stop` → `release()` incondicional (semântica T18 preservada, inclusive morte por heartbeat).

### SystemStateObserver (R19)

- Assina: `NSWorkspace.didWakeNotification`, `NSWorkspace.screensDidWakeNotification`, `NSWorkspace.sessionDidBecomeActiveNotification`, `CGDisplayRegisterReconfigurationCallback`.
- Único callback `onReassert(reason:)`, debounced (~1 s — wake dispara rajada de notificações).
- **Cliente**: se estado-alvo é `.locked` → recalcula park (topologia pode ter mudado) e re-`engage`.
- **Servidor**: se `remote == true` → re-suprime tap + re-dissocia + `CGEvent.tapEnable(true)` (wake pode desabilitar o tap silenciosamente — mesma classe do `tapDisabledByTimeout` já tratado) + re-hide.
- `NotificationCenter` injetado no init → testável sem dormir a máquina.

### Servidor em REMOTE: re-warp contínuo (R18)

Em `ServerSession.handleRemote(.mouseMoved)`, além de streamar o delta: `CGWarpMouseCursorPosition(parkPoint)` — `parkPoint` capturado no cruzamento (posição de saída, já disponível em `handleLocal`). Deltas do tap permanecem válidos com cursor pinado (`kCGMouseEventDeltaX/Y` independem da posição). Nota Deskflow: dissociação + warp convivem bem; warp não gera evento de tap (não realimenta).

### Scroll contínuo (R20) — protocolo v0.1+

Nova mensagem (tipo desconhecido é ignorado por decoders antigos — protocolo §2; `proto_version` permanece 1):

```
0x23 SCROLL_CONTINUOUS  S→C
  dx f32 · dy f32        # pixel deltas (positivo = direita/baixo, convenção do 0x22)
  phase u8               # 0=none 1=began 2=changed 3=ended 4=cancelled
  momentum u8            # 0=none 1=began 2=changed 3=ended
```

- **Captura** (`InputCapture`): `scrollWheel` → `isContinuous` (`kCGScrollWheelEventIsContinuous`)? → pixel deltas (`scrollWheelEventPointDeltaAxis1/2`) + `scrollWheelEventScrollPhase` + `scrollWheelEventMomentumPhase` → `CapturedEvent.scrollContinuous`; discreto → caminho atual (0x22, linhas).
- **Injeção** (`InputInjector`): `CGEvent(scrollWheelEvent2Source:units:.pixel,...)` + set dos campos `scrollPhase`/`momentumPhase`/`isContinuous=1`. Sem acúmulo de resto (pixels são inteiros na prática; frações descartadas ≤1 px).
- Momentum: fases retransmitidas do servidor (o trackpad de origem já gera a cauda de momentum — não sintetizamos nada, só repassamos).

### Autorepeat (R22) + supressão (R21)

- `InputCapture`: `keyDown` lê `kCGKeyboardEventAutorepeat` → `CapturedEvent.key(..., isRepeat:)`. Fio: **sem mudança** — repeat é gerado como keyDowns repetidos que já trafegam; o injetor marca autorepeat quando recebe keyDown de tecla **já pressionada** (`PressedKeys.currentlyPressed` já rastreia — zero bytes novos no protocolo).
- `InputInjector.init`: `source.localEventsSuppressionInterval = 0` (+ `setLocalEventsFilterDuringSuppressionState(.permitAllEvents, ...)` se o UAT mostrar resíduo).

### Coalescing + métricas (R23, R24)

- `InputMetrics` (struct thread-safe, contadores atômicos): incrementos nos pontos de captura/injeção/envio/warp/reassert; dump no log em `stop()` e a cada 60 s em nível debug.
- Coalescing: `ServerSession` já serializa em `queue`; trocar `transport.send([msg])` imediato por buffer drenado na própria queue — no drain, `mouseMove` consecutivos fundem (`dx+=`, `dy+=`). Fila vazia (caso comum) = comportamento idêntico ao atual, zero latência adicional. Só ativa se as métricas do T26 mostrarem backlog (fila > 1 em regime).

## Decisões técnicas

| Área | Decisão | Nota |
|---|---|---|
| Hide global | API privada via `dlsym`, fallback no-op | Única opção de fundo (DTS confirma); Dock-alvo devolve o cursor — aceito e documentado |
| Watchdog cliente | Poll 250 ms de `CGEvent(source:nil).location`, só enquanto travado | Zero TCC novo (tap/monitor global exigiriam Input Monitoring no cliente); 4 Hz invisível no Activity Monitor |
| Warp servidor | Por evento capturado (sem timer) | Tap já entrega os eventos; padrão lan-mouse |
| Park point | Borda de retorno (mantém R16) | Continuidade espacial; canto só se hide falhar E UAT reprovar |
| Fio do scroll | Mensagem nova 0x23, `proto_version` inalterado | Decoder antigo ignora tipo desconhecido (§2) — compat forward preservada |
| Autorepeat | Derivado no cliente via `PressedKeys` | Zero mudança de protocolo |
| Reassert | Debounce 1 s por rajada de notificações de wake | Reaplicar trava 2× é inócuo (idempotente) |

## Incertezas flagradas (verificar em spike/UAT, não assumir)

1. ~~**T19 — `SetsCursorInBackground` em macOS 26**~~ ✅ RESOLVIDA (2026-07-03, spike `macos/spikes/conceal-spike/`, macOS 27.0 build 26A5368g): `dlsym` resolve `_CGSDefaultConnection`+`CGSSetConnectionProperty`; `CGSSetConnectionProperty("SetsCursorInBackground", true)` → 0; `CGDisplayHideCursor` → 0. Técnica viável → R17 segue com API privada. Confirmação visual do "sumiu de fundo" fica pro UAT 3 (precisa 2 máquinas).
2. ~~**T19 — warp offscreen** (alternativa DTS)~~ ✅ RESOLVIDA: `CGWarpMouseCursorPosition((maxX+5000, maxY+5000))` **CLAMPA** de volta (landed 1439.98/899.98 numa tela 1440×900). Warp-offscreen NÃO serve de ocultação → fallback do R17 é só park-visible (seta parada). Sem alternativa sem API privada.
3. **T25 — apps respeitam fases sintéticas?** Rubber-band/momentum em Safari/Xcode com eventos `scrollWheelEvent2` + fases setadas via campo (evento não nasce de gesto). Se parcial: pixel scroll sem momentum ainda ≫ linhas — aceitar e registrar.
4. **Reset da dissociação**: causa exata (wake? screensaver? loginwindow?) não documentada. Design não depende da resposta (R18/R19 curam qualquer causa), mas o UAT 1–2 registra o comportamento observado para o STATE.
5. **Deltas com cursor pinado**: aceleração do sistema aplicada ou cru? Afeta "sensação" (kvm-mvp usa os mesmos deltas hoje — sem regressão possível, só registrar no UAT 8).

## Traceabilidade

R17→`CursorConcealer` (+config `concealCursor`) · R18→`CursorSentinel`+`SentinelPolicy`+re-warp em `ServerSession.handleRemote` · R19→`SystemStateObserver`+integração nas duas sessions · R20→`Message.scrollContinuous`+`InputCapture`+`InputInjector`+PROTOCOL.md 0x23+golden vectors · R21→`InputInjector.init` · R22→`InputCapture`+`InputInjector`+`PressedKeys` · R23→buffer de envio em `ServerSession` · R24→`InputMetrics`
