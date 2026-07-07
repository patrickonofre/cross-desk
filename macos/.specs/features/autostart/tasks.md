# Tasks — autostart

Gate padrão: `cd macos/CrossDeskKit && swift test` verde + build (`Scripts/make-app.sh`) sem warnings novos.
Status: ☐ pendente · ◐ em progresso · ☑ feito.

- ☑ **T58 — `LoginItem` wrapper** (R50, R51, R52, R53)
  - What: enum fino (padrão de `Permissions.swift`) sobre `ServiceManagement`: `status` (mapeia `SMAppService.mainApp.status`), `register()`/`unregister()` (repassam o throw, sem catch aqui), `openSettings()` (`SMAppService.openSystemSettingsLoginItems()`).
  - Where: `macos/CrossDeskKit/Sources/Autostart/LoginItem.swift`
  - Done when: compila, zero estado próprio (sem `@Published`, sem persistência) — só repassa a API do SO.
  - Tests: nenhum teste de unidade (API do SO, mesmo caso de `Permissions.swift` — não testável fora de um bundle assinado real).

- ☑ **T59 — Wiring em `AppState`** (R51, R53, R54) — depende de T58
  - What: `@Published var loginItemEnabled = false`, `@Published var loginItemNeedsApproval = false`; `refreshLoginItemStatus()` (lê `LoginItem.status`, atualiza as duas flags); `toggleLoginItem()` (chama `register()` ou `unregister()` conforme `loginItemEnabled` atual, `catch` loga via `Log.app.error` e não propaga, sempre termina chamando `refreshLoginItemStatus()`). Chamar `refreshLoginItemStatus()` uma vez em `init()`, junto de `refreshPermissions()`.
  - Where: `macos/CrossDeskKit/App/AppState.swift`
  - Done when: build limpo; nenhum novo campo em `AppConfig` (checar `ConfigStore.swift` continua sem mudança — R51/decisão assumida).
  - Tests: nenhum (mesma razão de T58 — lógica é só repasse pro wrapper).

- ☑ **T60 — UI em `MenuBarView`** (R50, R52) — depende de T59
  - What: `Toggle` "Abrir ao iniciar sessão" na `optionsSection` (ao lado de "Esconder o cursor"), binding customizado (`get: appState.loginItemEnabled`, `set: { _ in appState.toggleLoginItem() }` — nunca escreve o bool direto, só dispara a ação e deixa o refresh corrigir a UI). Se `appState.loginItemNeedsApproval`: caption + botão "Abrir Ajustes" chamando o wrapper. Adicionar `appState.refreshLoginItemStatus()` no mesmo bloco que já chama `refreshPermissions()` (`onAppear` + `Timer.publish(every: 2...)` em `MenuBarView`) — sem timer novo.
  - Where: `macos/CrossDeskKit/App/MenuBarView.swift` (`optionsSection`, `onAppear`, `onReceive`)
  - Done when: toggle visível, aviso de aprovação some quando `.enabled`.
  - Tests: nenhum (view SwiftUI sem lógica nova além do binding).

- ☑ **T61 — UAT manual** (aceitações 1–6 do `spec.md`) — ✅ 2026-07-07, usuário reportou as 6 passando (incl. restart real), sem bugs.
  - What: rodar as 6 aceitações do spec numa máquina real — inclui restart/logout (não dá pra automatizar, `SMAppService` só reage a estado real de sessão do SO).
  - Where: máquina de desenvolvimento (build assinado via `make-app.sh`).
  - Done when: 6/6 aceitações OK; qualquer desvio vira nota em `STATE.md` (padrão do projeto).
  - Requer: Ajustes do Sistema acessível, permissão pra restart/logout de teste.
