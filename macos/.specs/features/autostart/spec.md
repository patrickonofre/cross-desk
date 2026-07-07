# Spec — autostart (abrir CrossDesk ao iniciar sessão)

**Escopo:** Medium (contido: 1 arquivo novo pequeno + wiring em `AppState`/`MenuBarView`, zero mudança de protocolo). Pipeline: spec → tasks → execute (design dispensado — decisão de API já tomada em `PROJECT.md`: "Autostart: SMAppService (pós-MVP)").

**Contexto:** App roda como relay de fundo (menubar, `LSUIElement`) — hoje o usuário precisa abrir manualmente depois de cada login/restart. Item já previsto no stack do projeto, nunca implementado.

## Verificação técnica (Knowledge Verification Chain)

- **SMAppService (`ServiceManagement`, macOS 13+), variante `mainApp`**: registra a própria app como item de login sem helper/plist separado (diferente da API legada `SMLoginItemSetEnabled`). Alvo mínimo do projeto já é macOS 14 — acima do piso exigido.
- **Fonte de verdade única**: `SMAppService.mainApp.status` é o estado real — o usuário pode desligar por fora, direto em Ajustes > Itens de Login. Mesma classe de risco já documentada em `STATE.md` sobre TCC ("toggle ligado na UI, preflight falha" quando duas fontes divergem) — aqui a cura é a mesma: **não persistir bool em `AppConfig`/`config.json`**, o toggle sempre lê/escreve o status do SO diretamente.
- **`.requiresApproval`**: primeira chamada a `register()` fica pendente até o usuário aprovar em Ajustes > Itens de Login. `SMAppService.openSystemSettingsLoginItems()` abre o painel certo direto — mesma família de API, mesmo padrão que `Permissions.swift` já usa pros painéis de TCC (Input Monitoring/Accessibility).
- **`register()`/`unregister()` lançam erro** — chamada síncrona e rápida, segura na main actor (`AppState` já é `@MainActor`). Padrão de tratamento igual ao catch de `startFileTransfer`: loga e degrada sem derrubar o app.

## Requisitos

- **R50** — Toggle na UI (`MenuBarView`, ao lado de "Esconder o cursor") liga/desliga abrir no login via `SMAppService.mainApp.register()`/`.unregister()`.
- **R51** — Estado exibido é sempre o status real do SO (`SMAppService.mainApp.status`), sem bool próprio persistido; refresh reaproveita o mesmo poll de 2s que já existe pra TCC (`onAppear` + `Timer` em `MenuBarView`).
- **R52** — Status `.requiresApproval` mostra aviso + botão "Abrir Ajustes" (`SMAppService.openSystemSettingsLoginItems()`) — mesma UX de permissão pendente já usada pra Input Monitoring/Accessibility.
- **R53** — Falha em `register()`/`unregister()` (throw) não derruba o app — loga erro (`Log.app.error`), UI volta a refletir o status real (possivelmente inalterado).
- **R54** — Default desligado (opt-in). Instalar/atualizar o app não liga autostart sozinho.

## Fora de escopo

| Item | Motivo |
| --- | --- |
| Auto-iniciar servidor/cliente (sessão) ao abrir no login | Pedido foi "abrir ao iniciar" (launch-at-login), não "conectar sozinho" — sessão continua manual via botão Iniciar/Parar. Ideia separada se quiser depois. |
| Suporte a macOS < 13 | Alvo mínimo do projeto já é 14 (Sonoma); `SMAppService` exige 13+. |
| Mover `CrossDesk.app` pra `/Applications` automaticamente | `SMAppService` funciona a partir do caminho atual (mesma identidade de assinatura estável já usada pra TCC sobreviver a rebuilds). Só vira problema se o usuário mover a pasta depois de registrar — Ajustes > Itens de Login ficaria com entrada órfã (limitação conhecida da API, não deste app). |

## Aceitação (UAT)

1. Instalação nova: toggle "Abrir ao iniciar sessão" aparece desligado.
2. Ligar o toggle → entrada aparece em Ajustes do Sistema > Geral > Itens de Login (habilitada ou pendente de aprovação).
3. Se pendente: botão "Abrir Ajustes" leva direto ao painel certo; aprovar lá reflete "ligado" na app em até 2s (poll).
4. Desligar o toggle remove a entrada de Itens de Login.
5. Restart (ou logout/login) com toggle ligado → CrossDesk abre sozinho no menubar.
6. Desabilitar a entrada direto em Ajustes > Itens de Login (sem tocar no app) → reabrir o painel do CrossDesk reflete "desligado" em até 2s.

## Decisões assumidas (fácil de mudar se incomodar)

- Nome/identidade da entrada de login: bundle identifier atual (`dev.crossdesk.mac`) via `mainApp` — nada pra configurar.
- Sem novo campo em `AppConfig`/`config.json` (R51) — decisão deliberada contra duplicar fonte de verdade (mesma lição do TCC).
