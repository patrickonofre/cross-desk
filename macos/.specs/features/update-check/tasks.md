# Tasks — update-check

Gate padrão: `cd macos/CrossDeskKit && swift test` verde + build (`Scripts/make-app.sh`) sem warnings novos.
Status: ☐ pendente · ◐ em progresso · ☑ feito.

- ☑ **T62 — `UpdateChecker` service** (R55, R57, R61) — ✅ 2026-07-07
  - What: módulo fino em `Sources/UpdateCheck/`: protocolo mínimo pra injeção de rede
    (`HTTPClient` com `func data(for: URLRequest) async throws -> (Data, URLResponse)` —
    `URLRequest`, não `URL`: GitHub rejeita chamada sem header `User-Agent` com 403, só dá
    pra setar header via `URLRequest` — `URLSession` conforma de graça),
    `struct ReleaseInfo: Equatable, Sendable { version: String; url: URL }`,
    `func checkLatestRelease(currentVersion: String, client: some HTTPClient = URLSession.shared) async -> ReleaseInfo?`
    (`nil` = sem update OU erro — R61 não distingue os dois pro chamador), comparador puro
    `func isNewer(_ remote: String, than local: String) -> Bool` (strip `v`, strip sufixo
    `-...`/`+...`, split `.`, compara `[Int]` componente a componente, tag malformada → `false`).
  - Where: `macos/CrossDeskKit/Sources/UpdateCheck/UpdateChecker.swift`
  - Done when: compila; `checkLatestRelease` nunca lança, sempre retorna `ReleaseInfo?`. ✅
  - Tests: `Tests/UpdateCheckTests/UpdateCheckerTests.swift` — 13 casos (comparador: igual,
    maior, menor, prefixo `v`, sufixo `-beta`, tag malformada/vazia, componentes de tamanho
    diferente, "1.10.0" > "1.9.0" não-lexicográfico; `checkLatestRelease`: sucesso, sem
    update, JSON malformado, HTTP 404, erro de rede) via `FakeHTTPClient` injetado. **Correção
    de spec**: `Tests/` **não** estava vazio (27 arquivos em pastas por módulo, ex.
    `TransportTests/PairingKeyTests.swift`) — a spec original assumiu errado ao só checar
    `Tests/` na raiz sem olhar as subpastas. Framework confirmado por essas: XCTest
    (`@testable import CrossDeskKit`, `XCTestCase`) — `UpdateCheckTests/` segue o mesmo
    padrão de pasta-por-módulo. Gate: `swift test` → 190/190 verde (13 novos + 177
    existentes, zero regressão).

- ☑ **T63 — Wiring em `AppState`** (R55, R56, R58, R59, R60, R61, R62) — ✅ 2026-07-07 — depende de T62
  - What: `AppConfig` ganha `dismissedUpdateVersion: String = ""` (tolerant decode, mesmo
    padrão de `concealCursor`/`firstCrossingDone` — `decodeIfPresent(...) ?? default`).
    `AppState` ganha `@Published var availableUpdate: UpdateChecker.ReleaseInfo?`;
    `refreshUpdateCheck()` (chama `UpdateChecker.checkLatestRelease`, só publica em
    `availableUpdate` se `result.version` for mais novo que `config.dismissedUpdateVersion`
    E mais novo que a versão instalada — R60); `dismissUpdate()` (persiste
    `config.dismissedUpdateVersion = availableUpdate.version`, `saveConfig()`, limpa
    `availableUpdate`); `openUpdateDownload()` (`NSWorkspace.shared.open(availableUpdate.url)`).
    Scheduling: `refreshUpdateCheck()` uma vez em `init()` dentro de `Task { }` (não bloqueia
    o launch) + `Timer.scheduledTimer(withTimeInterval: 86400, repeats: true)` guardado como
    propriedade privada do `AppState` — **não** o mesmo timer de 2s do `MenuBarView` (esse só
    roda com popover aberto).
  - Where: `macos/CrossDeskKit/App/AppState.swift`
  - Done when: build limpo; `ConfigStore`/`AppConfig` continuam decodificando configs
    antigos sem a chave nova; timer sobrevive com popover fechado (propriedade do
    `AppState`, não da view).
  - Tests: nenhum (wiring fino repassando pro `UpdateChecker` já testado em T62 — mesma
    razão do T59 de autostart).

- ☑ **T64 — UI em `MenuBarView`** (R58, R59, R60, R62) — ✅ 2026-07-07 — depende de T63
  - What: nova `updateSection` entre `optionsSection` e `permissionsSection`. Só quando
    `appState.availableUpdate != nil`: `HStack` com ícone `arrow.down.circle.fill`,
    `Text("Nova versão \(version) disponível")`, `Button("Baixar")` →
    `appState.openUpdateDownload()`, `Button("Ignorar")` → `appState.dismissUpdate()`.
    `Button("Verificar agora")` (R62) sempre visível abaixo, chamando
    `appState.refreshUpdateCheck()` direto.
  - Where: `macos/CrossDeskKit/App/MenuBarView.swift` (`updateSection`, chamada no `body`
    entre `optionsSection` e `permissionsSection`)
  - Done when: rótulo aparece/some conforme `availableUpdate` (`if let`, sem placeholder
    quando `nil` — R59); `swift build` + `make-app.sh` limpos, zero warning novo. ✅
  - Tests: nenhum (view SwiftUI sem lógica nova além do binding — mesma razão do T60 de
    autostart). **Verificação visual real (popover aberto) não foi feita por automação**:
    computer-use já não conseguiu resolver esse build dev antes (achado registrado em
    `macos/.specs/project/STATE.md` — Launch Services não indexa `build/CrossDesk.app`) e
    não é instalado como app "de verdade". Fica para o UAT manual (T65).

- ☐ **T65 — UAT manual** (aceitações 1–6 do `spec.md`)
  - What: rodar as 6 aceitações numa build real (`make-app.sh`) — inclui simular versão
    antiga (`CFBundleShortVersionString` de teste) pra forçar o caminho "tem update", já que
    o release real publicado (1.0.0) é igual à versão instalada.
  - Where: máquina de desenvolvimento, build assinado.
  - Done when: 6/6 aceitações OK; qualquer desvio vira nota em `STATE.md` (padrão do
    projeto).
