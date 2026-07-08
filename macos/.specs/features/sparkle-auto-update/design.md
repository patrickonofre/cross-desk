# Design — sparkle-auto-update

## Arquitetura

```
Package.swift
  └─ CrossDeskApp (executable target) ──depends on──> Sparkle (SPM, binary target/xcframework)
        │                                    (CrossDeskKit lib NÃO depende — testes ficam limpos)
        ▼
  SparkleUpdateService (App/, novo)
        │  wraps SPUStandardUpdaterController
        │  probeForUpdateInformation() → checagem passiva (launch/24h, sem UI)
        │  checkForUpdates()           → checagem interativa (botão), Sparkle mostra a UI dele
        │  onAvailableVersionChange    → callback pro AppState atualizar o rótulo discreto
        ▼
  AppState.availableUpdate: String?  (só a versão — Sparkle já sabe a URL/enclosure)
        ▼
  MenuBarView.updateSection  (rótulo + botões "Instalar"/"Ignorar" + "Verificar Atualizações")
```

## Decisões

**Sem Xcode project.** mac-metrics-view embute Sparkle via `.xcodeproj` (link automático de
framework+XPC pelo Xcode). cross-desk é SPM puro — Sparkle 2.x se resolve como dependência SPM
normal (`Package.swift`) e o `.framework`/XPCs saem em
`.build/artifacts/sparkle/Sparkle.xcframework/...` após `swift build`. `make-app.sh` já monta o
`.app` manualmente (copia binário, Info.plist, ícone) — só precisa ganhar 2 passos novos: copiar
o framework pra `Contents/Frameworks/` e assinar tudo de dentro pra fora antes do bundle final
(mesma ordem do `sign-app.sh` do mac-metrics-view).

**Sem `#if canImport(Sparkle)` / `NoOpUpdateService`.** Esse gate existe no mac-metrics-view
porque o mesmo código-fonte compila em DOIS alvos (app Xcode com Sparkle linkado E executável SPM
sem framework, pra `swift run`/`swift test` funcionar sem framework nenhum embutido). cross-desk
não tem esse segundo alvo — `CrossDeskApp` é o único executável e sempre é distribuído via
`make-app.sh`. `CrossDeskKitTests` testa só a lib (`CrossDeskKit`), que nunca importa Sparkle.
Então: import direto, sem gate, sem no-op — dependência sempre presente onde é usada.

**Onde mora o código novo.** `App/SparkleUpdateService.swift` (não em `Sources/`) — mesma pasta
de `AppState.swift`, porque só o executável (`CrossDeskApp`) depende de Sparkle no
`Package.swift`; colocar em `Sources/` (alvo `CrossDeskKit`) vazaria a dependência pro
`CrossDeskKitTests`.

**`UpdateChecker` (Sources/UpdateCheck/) fica só com a comparação de versão.** `isNewer` /
`displayVersion` continuam necessários — não pra decidir "tem update" (isso agora é o appcast +
Sparkle), mas pra decidir se uma versão encontrada é mais nova que `dismissedUpdateVersion`
(R60 antigo, mantido: "Ignorar" não pode voltar a aparecer pra mesma versão). `checkLatestRelease`
/`ReleaseInfo`/`HTTPClient`/`GitHubRelease` saem — Sparkle já faz o fetch+parse do appcast, não
tem mais chamada de rede nossa pra testar aqui.

**UI passiva vs. interativa (mantém P2).** `SPUStandardUserDriverDelegate` com
`supportsGentleScheduledUpdateReminders = true` +
`standardUserDriverShouldHandleShowingScheduledUpdate(...) = false` — igual ao mac-metrics-view.
Isso faz o Sparkle NÃO estourar o painel de update sozinho quando a checagem é automática
(launch/24h); ele só chama o delegate (`onAvailableVersionChange`), que atualiza o rótulo
discreto do `MenuBarView` (já existe, R58). Quando o usuário clica em "Instalar" ou "Verificar
Atualizações", aí sim `checkForUpdates()` roda o fluxo interativo completo do Sparkle.

**Timer de 24h manual (`AppState.updateCheckTimer`) é removido.** Sparkle já agenda sozinho via
`SUScheduledCheckInterval` (Info.plist) + `SUEnableAutomaticChecks`. Duplicar teria dois relógios
concorrentes checando a mesma coisa.

**Hospedagem do appcast: GitHub Pages a partir de `docs/` na raiz do repo**, igual ao
mac-metrics-view (`patrickonofre.github.io/cross-desk/appcast.xml`). Requer 1 ação manual única
(habilitar Pages no repo) — feita com o usuário, não pelo agente (visível externamente).

**Enclosure do appcast aponta pro asset do GitHub Release já existente**
(`.../releases/download/vX.Y.Z/CrossDesk.zip`), não duplica o zip dentro de `docs/downloads/`
como o mac-metrics-view faz. Motivo: cross-desk já publica esse asset a cada release (fluxo
atual, manual); duplicar o binário dentro do git do site infla o repo sem necessidade — mesmo
efeito final pro usuário (download direto, sem passar pelo navegador), só muda ONDE o zip mora.

**Assinatura de código aninhada em `make-app.sh`** (novo passo, adaptado do `sign-app.sh` do
mac-metrics-view): assina de dentro pra fora — XPCs do Sparkle (`Downloader.xpc`,
`Installer.xpc`) → `Autoupdate`/`Updater.app` → o `.framework` → o `.app` principal. Sem isso o
`codesign --verify --deep --strict` falha e o Gatekeeper recusa o bundle nas máquinas dos
usuários.

**Chave EdDSA:** gerada 1 vez pelo usuário com a própria ferramenta do Sparkle
(`generate_keys`, binário que vem no pacote SPM resolvido). Fica no Keychain do usuário — o
agente nunca vê a chave privada. A pública vai pro `Info.plist` (`SUPublicEDKey`) depois de
gerada; até lá o campo fica com um placeholder marcado.

## Componentes afetados

| Arquivo | Mudança |
| --- | --- |
| `CrossDeskKit/Package.swift` | + dependência Sparkle, só no target `CrossDeskApp` |
| `CrossDeskKit/App/SparkleUpdateService.swift` | novo — wrapper do `SPUStandardUpdaterController` |
| `CrossDeskKit/App/AppState.swift` | remove timer/GitHub-check, usa `SparkleUpdateService` |
| `CrossDeskKit/App/MenuBarView.swift` | renomeia botões, `Baixar`→`Instalar` chama `checkForUpdates()` |
| `CrossDeskKit/Sources/UpdateCheck/UpdateChecker.swift` | remove fetch GitHub, mantém `isNewer` |
| `CrossDeskKit/Tests/UpdateCheckTests/UpdateCheckerTests.swift` | remove os 5 testes de `checkLatestRelease` |
| `macos/Scripts/make-app.sh` | + Sparkle no Info.plist, embute framework, assina aninhado |
| `docs/appcast.xml` (raiz do repo, novo) | feed inicial (infra manual: Pages) |
| `macos/Scripts/sparkle-sign-release.sh` (novo) | helper: roda `sign_update` e imprime o item pro appcast |
