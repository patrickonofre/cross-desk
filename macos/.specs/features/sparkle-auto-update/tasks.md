# Tasks — sparkle-auto-update

| # | What | Depends on | Done when |
| --- | --- | --- | --- |
| T1 | `Package.swift`: dependência Sparkle (SPM), linkada só em `CrossDeskApp` | - | `swift build --product CrossDeskApp` resolve o pacote |
| T2 | `App/SparkleUpdateService.swift`: wrapper (`probeForUpdateInformation`, `checkForUpdates`, `onAvailableVersionChange`, delegate gentle-reminder) | T1 | compila, sem warning |
| T3 | `AppState`: substitui timer+`UpdateChecker.checkLatestRelease` por `SparkleUpdateService`; `availableUpdate: String?` | T2 | `dismissUpdate`/R60 continuam funcionando com `isNewer` |
| T4 | `MenuBarView`: renomeia botões ("Verificar Atualizações", "Instalar") | T3 | build limpo |
| T5 | `UpdateChecker.swift` + testes: remove fetch GitHub, mantém `isNewer` | - | 8 testes de `isNewer` verdes, 5 de `checkLatestRelease` removidos |
| T6 | `make-app.sh`: Info.plist ganha chaves Sparkle (placeholder na chave pública), embute `Sparkle.framework`, assina aninhado | T1 | `codesign --verify --deep --strict` limpo no `.app` gerado |
| T7 | `docs/appcast.xml` (raiz) + `scripts/sparkle-sign-release.sh` | - | arquivo válido (RSS bem formado) |
| T8 | **Manual (usuário):** gerar chave EdDSA, habilitar GitHub Pages, colar chave pública no Info.plist, publicar 1º release assinado | T1-T7 | app real checa e instala sozinho |

Sequencial (sem `[P]` — poucos arquivos, mudança concentrada). T8 fica fora do agente
(custódia de chave + infra externa visível).
