# Tasks — layout-ux

Numeração continua do projeto (última: T48). Gate padrão: `cd macos/CrossDeskKit && swift test` verde + build `macos/Scripts/make-app.sh` OK. `[P]` = paralelizável.

Convenção de testes (precedente T46): lógica no kit = unit via `swift test`; views SwiftUI finas = UAT. Toda lógica de projeção/snap/fase vive no `DeskModel` (testável), views só desenham.

Status: **T49–T56 ✅ (2026-07-05, 166 testes verdes — +15 da feature, app assina)** — code-complete. Pendente: T57 (UAT 2 macs).

- T52 notas: `ClientSession.handle(_:)` extraído de `wire()` (testável com eventos sintéticos); init ganhou `sentinelEffects:` injetável (efeitos no-op nos testes — sem warp/dissociação reais na máquina de teste). `onEnter`/`onLeave` disparam antes do `apply`.
- T53/T54 notas: transform desk→view (scale-to-fit + origin) duplicada de propósito nas duas views (nenhuma lógica de decisão, só desenho); `NSApp.activate()` (variante `ignoringOtherApps:` deprecada no SDK 14). Cliente sem ENTER: tile no oposto do default com legenda "posição aparece após a primeira travessia".
- T55 notas: ícone REMOTE = `cursorarrow.motionlines` (sujeito a veto no UAT); dica R39 só no papel servidor (empurrar o cursor é ação de quem tem o teclado — cliente apenas marca `firstCrossingDone` no 1º ENTER).
- T56 notas: labels/traits entregues inline nas views (summary do canvas, tile, mini-mapa como botão, picker segmentado como caminho de teclado na janela E no painel). Passada com Accessibility Inspector fica no roteiro do T57 (exige app rodando).

## T49 — Displays: DisplayInfo com isBuiltin + nome `[P]`

- **What:** `Displays` passa a expor `[DisplayInfo]` (bounds CG, `isBuiltin` via `CGDisplayIsBuiltin`, nome via `NSScreen.localizedName` casado por `deviceDescription["NSScreenNumber"]`). `activeBounds()` mantido (EdgeDetector/ScreenTopology intocados).
- **Where:** `Sources/Displays.swift`
- **Depends on:** — · **Reuses:** `Displays.activeBounds()`
- **Done when:** em máquina com display, `infos()` retorna ≥1 item com bounds válidos e nome não-vazio; API antiga compila sem mudança nos call sites.
- **Tests:** unit (count/bounds/consistência com activeBounds; nada que dependa de hardware específico).

## T50 — DeskModel: projeção topologia + fases + snap

- **What:** novo target/pasta `Sources/UI/`: normalização da união das telas → retângulos 0–1, `peerSlot(edge:)`, `edge(fromDrop:)` (maior distância projetada; empate → mantém atual), `DeskPhase` derivada de `SessionState` + `paired` + `TransferUIState` (tabela R38), visibilidade do coach-mark (R39: pareado && !firstCrossingDone).
- **Where:** `Sources/UI/DeskModel.swift`, `Package.swift`
- **Depends on:** T49 · **Reuses:** `EdgeSide`, `SessionState`, `TransferUIState`
- **Done when:** snap correto nos 4 lados com topologia de 2 monitores desalinhados; drop dentro da união não muda borda; cada `SessionState` mapeia para exatamente uma `DeskPhase`.
- **Tests:** unit (snap ×4 + canto + interno; fases ×6; normalização com monitor vertical).

## T51 — Config: flag firstCrossingDone `[P]`

- **What:** `AppConfig.firstCrossingDone: Bool` persistido, `decodeIfPresent ?? false` (lição do `concealCursor`: chave ausente não pode quebrar load).
- **Where:** `Sources/Config/`
- **Depends on:** — · **Reuses:** padrão tolerante do `init(from:)`
- **Done when:** config antigo (sem a chave) carrega com `false`; roundtrip save/load preserva `true`.
- **Tests:** unit no ConfigStoreTests.

## T52 — Client: expor lastEnterEdge `[P]`

- **What:** `ClientSession` publica a borda de entrada do último ENTER (`lastEnterEdge: EdgeSide?`, nil até o primeiro ENTER) no callback de estado existente — insumo do canvas read-only do cliente (R37).
- **Where:** `Sources/Client/`
- **Depends on:** — · **Reuses:** pipeline de estado existente da ClientSession
- **Done when:** ENTER processado → edge publicado; LEAVE não apaga (mantém último); reconexão preserva nil/último conforme sessão nova/mesma.
- **Tests:** unit (injeção de ENTER sintético no parser da sessão).

## T53 — Janela "Telas": DeskCanvasView + cena Window

- **What:** cena `Window("Telas", id: "desk")` no app (LSUIElement mantido); canvas: monitores locais (silhueta laptop p/ isBuiltin, nome), tile do peer; **servidor**: drag com pré-visualização da borda + snap → `config.edgeSide` + `saveConfig()` + aviso "aplica ao reiniciar a sessão" quando running; **cliente**: read-only em `lastEnterEdge`, legenda "definido pelo servidor", posição neutra + "aparece após a primeira travessia" enquanto nil; fases R38 (vazio/pareando/conectado/controlando/erro + overlay de transferência); recompute em `didChangeScreenParametersNotification`.
- **Where:** `App/DeskCanvasView.swift`, `App/CrossDeskApp.swift`
- **Depends on:** T50, T51, T52 · **Reuses:** `DeskModel` (toda a lógica), `AppState`
- **Done when:** compila e abre via `openWindow`; drag muda `edgeSide` persistido; estados renderizam conforme tabela R38; monitor plugado/removido com janela aberta reorganiza sem crash.
- **Tests:** lógica já coberta no T50; view → UAT T57. Gate: `swift test` + make-app.sh.

## T54 — Painel: MiniMapView + abrir janela

- **What:** mini-mapa no topo do `MenuBarView` (mesma projeção do DeskModel em escala menor, sem drag; ponto de foco, borda, chip de transferência); clique/botão "Organizar telas…" → `openWindow("desk")`. Status textual permanece (R40).
- **Where:** `App/MiniMapView.swift`, `App/MenuBarView.swift`
- **Depends on:** T53 · **Reuses:** `DeskModel`, seção de transferência existente
- **Done when:** mapa reflete `sessionState` ao vivo (<1 s); clique abre a janela; painel continua funcional com sessão parada.
- **Tests:** projeção no T50; view → UAT T57.

## T55 — Ícone dinâmico + coach-mark de travessia

- **What:** R41: symbol do `MenuBarExtra` varia em `controllingRemote` (volta em LOCAL/parado). R39: dica direcional única ("Empurre o cursor pela borda direita/esquerda/cima/baixo") no painel e na janela enquanto `DeskModel` mandar; seta `firstCrossingDone=true` na primeira transição p/ REMOTE (servidor) / primeiro ENTER (cliente).
- **Where:** `App/CrossDeskApp.swift`, `App/MenuBarView.swift`, `App/AppState.swift`
- **Depends on:** T51, T54 · **Reuses:** flag do T51, visibilidade do T50
- **Done when:** dica aparece só entre parear e 1ª travessia, nunca depois (sobrevive restart via config); ícone alterna nos dois sentidos.
- **Tests:** condição de visibilidade unit (T50); persistência unit (T51); visual → UAT T57.

## T56 — Acessibilidade (R40)

- **What:** labels de VoiceOver no mini-mapa, canvas, tile e monitores ("MacBook de Ana, à direita das suas telas"; "foco neste Mac"); ordem de foco por teclado na janela; confirmar picker de borda como caminho 100 % teclado; estado nunca só por cor (texto presente em toda fase).
- **Where:** `App/*.swift` (views da feature)
- **Depends on:** T53, T54, T55
- **Done when:** Accessibility Inspector sem erro nas views novas; VoiceOver lê estado + borda sem tocar no canvas.
- **Tests:** checklist manual (Inspector) + UAT T57.

## T57 — UAT (2 macs) — aceitações R35–R41

- **What:** roteiro: mini-mapa segue foco em <1 s (R35); canvas reflete topologia real e monitor removido ao vivo (R36); arrastar direita→cima persiste e vale no próximo start, picker e canvas nunca divergem (R37); tabela de fases completa incl. transferência (R38); coach some após 1ª travessia e não volta pós-restart (R39); VoiceOver (R40); ícone (R41). Falhas viram tasks.
- **Depends on:** T56 · **Done when:** checklist assinado aqui. Candidato a entrar na sessão de UAT consolidado (junto de T28/T38/T47) se a implementação chegar antes.
- ✅ **2026-07-07** — usuário reportou aceitações R35–R41 passando (roteiro `UAT-1.0.md` bloco D), sem bugs. **T57 fechado.**

## Ordem

```
Fase 1 [P]: T49, T51, T52
Fase 2:     T49 → T50
Fase 3:     (T50,T51,T52) → T53 → T54 → T55 → T56 → T57
```

Cross-check deps ↔ diagrama: T50←T49 ✓ · T53←T50,T51,T52 ✓ · T54←T53 ✓ · T55←T51,T54 ✓ · T56←T53,T54,T55 ✓ · T57←T56 ✓ · [P] da Fase 1 sem deps entre si ✓. T53/T54/T55 sequenciais de propósito: compartilham `CrossDeskApp.swift`/`MenuBarView.swift` (paralelo = conflito de merge).

R42 (zero protocolo) é guarda transversal: nenhuma task toca `Sources/Protocol/` além de imports.
