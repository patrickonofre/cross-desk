# Spec — update-check (avisar nova versão disponível)

**Escopo:** Medium (contido: 1 módulo novo pequeno em `Sources/UpdateCheck/` + wiring em
`AppState`/`MenuBarView` + 1 campo tolerante em `AppConfig`, zero mudança de protocolo).
Pipeline: spec → tasks → execute (design dispensado — decisões de mecanismo/UI/cadência/
dismiss já tomadas com o usuário, ver abaixo).

**Contexto:** CrossDesk 1.0.0 publicado no GitHub (releases, distribuição zip ad-hoc). Hoje
o usuário só descobre versão nova visitando o repo manualmente. Feature de referência
(`mac-metrics-view`, `docs/ai/specs/spec-auto-update-sparkle.md` +
`spec-update-controls-simplify.md`) usa Sparkle — framework completo, `appcast.xml`
hospedado, download + instalação assinada EdDSA dentro do app. **Não replicado aqui**:
cross-desk é SPM puro sem Xcode project (`Package.swift`: lib `CrossDeskKit` + executável
`CrossDeskApp`, sem alvo Xcode pra embutir framework+XPC), sem CI, assinatura self-signed
estável via `make-app.sh`, e já tem incidente documentado (`STATE.md` raiz e
`macos/.specs/project/STATE.md`) de troca de bundle quebrando TCC nas duas máquinas antes da
identidade de assinatura ser estabilizada. Introduzir Sparkle repetiria essa classe de risco
sem necessidade.

## Decisões do usuário (perguntadas antes de especificar)

- **Mecanismo:** GitHub Releases API (`api.github.com/repos/patrickonofre/cross-desk/releases/latest`),
  não Sparkle. Sem dependência nova, sem tocar no bundle rodando.
- **Onde avisar:** label discreto no popover (`MenuBarView`) — mesmo padrão final do
  mac-metrics-view (`spec-update-controls-simplify`). Sem badge no ícone da menu bar.
- **Frequência:** checagem no launch + periódica (~24h) enquanto o app roda.
- **Dispensar versão:** sim — botão "Ignorar esta versão" persiste a versão ignorada; aviso
  só volta quando uma versão MAIS NOVA que a ignorada aparecer.

## Verificação técnica (Knowledge Verification Chain)

- **Sem dependência nova.** `URLSession` (Foundation) basta —
  `api.github.com/repos/.../releases/latest` retorna JSON com `tag_name` e `html_url`. Esse
  endpoint já exclui prereleases/drafts (comportamento documentado da API do GitHub) — não
  precisa filtro manual.
- **Testabilidade no padrão do repo** (`ConfigStore.fileURL` injetável; mac-metrics-view
  injeta `UserDefaults` fake): abstrair a chamada de rede atrás de um protocolo mínimo
  (`func data(for: URLRequest) async throws -> (Data, URLResponse)`) que `URLSession` já
  satisfaz estruturalmente — permite teste de unidade sem rede real. `URLRequest`, não
  `URL`: a API do GitHub devolve 403 sem header `User-Agent`, só dá pra setar via
  `URLRequest`.
- **Versão instalada = `CFBundleShortVersionString`** (`Bundle.main.infoDictionary`), não
  `CFBundleVersion` (esse é o build number "17", já lido em `AppState.init()` só pra log —
  não serve pra comparar contra a tag do GitHub, que segue o estilo `MARKETING_VERSION`
  "1.0.0").
- **Comparação numérica, não lexicográfica.** Tag do GitHub vem como `v1.0.0` (prefixo `v`
  confirmado nas tags reais) — remover o `v`, cortar qualquer sufixo `-...`
  (prerelease/build metadata, defensivo), split por `.`, comparar componente a componente
  como `Int` (mesma classe de bug que um comparador de string erraria: "1.10.0" vs "1.9.0").
- **Timer de 24h não reusa o `Timer.publish(every: 2...)` de `MenuBarView`** — aquele só
  dispara com o popover aberto (TCC/login-item toleram esse gap; update-check não pode,
  o app passa a maior parte do tempo com popover fechado). Scheduling vive em `AppState`
  (processo inteiro), não na view.
- **Persistência no padrão tolerante de `AppConfig`** (mesma técnica de
  `concealCursor`/`firstCrossingDone`): novo campo `dismissedUpdateVersion: String` default
  `""`, `decodeIfPresent(...) ?? default` no `init(from:)` — config antigo sem a chave
  carrega normal.
- **Sem i18n** — cross-desk não tem camada de localização (todo `MenuBarView` é string
  literal em pt-BR); string do aviso é hardcoded direto, sem `Strings`/`Localization`.
- **Abrir a página da release:** `NSWorkspace.shared.open(url)`.

## Requisitos

- **R55 — Checagem no launch.** Ao iniciar, `AppState` dispara checagem contra a GitHub
  Releases API em background — não bloqueia o launch, não trava a UI.
- **R56 — Checagem periódica (~24h).** Enquanto o app roda, repete a checagem a cada 24h
  via timer no nível do `AppState`, independente do popover estar aberto ou fechado.
- **R57 — Comparação correta de versão.** Considera "nova" só uma tag cujo valor numérico
  (`major.minor.patch`, prefixo `v` e sufixo `-...` removidos) seja MAIOR que
  `CFBundleShortVersionString` instalado — comparação por componente `Int`, nunca string.
- **R58 — Aviso no popover.** Quando há versão nova (R57) e ela não foi ignorada (R60),
  `MenuBarView` exibe rótulo discreto "Nova versão x.x.x disponível" com botão "Baixar" que
  abre `html_url` da release no navegador padrão.
- **R59 — Sem versão nova → sem aviso.** Nenhum texto placeholder quando não há update
  (mesma regra do mac-metrics-view, FR-3 de `spec-update-controls-simplify`).
- **R60 — Ignorar esta versão.** Botão ao lado do aviso (R58) persiste a versão anunciada em
  `AppConfig.dismissedUpdateVersion` e esconde o aviso imediatamente. Aviso só reaparece
  quando uma tag MAIS NOVA que `dismissedUpdateVersion` for encontrada — não quando a mesma
  tag ignorada continuar sendo a `latest`.
- **R61 — Falha silenciosa.** Sem rede, API fora do ar, rate limit ou JSON inesperado: a
  checagem falha sem crash, sem erro visível ao usuário, sem alterar o aviso atual — tenta
  de novo no próximo ciclo (R56).
- **R62 — Checagem manual (P2).** Botão "Verificar agora" reusa a função de R55/R57 pra
  forçar um ciclo sem esperar 24h. Não pedido explicitamente, mas custo marginal (mesma
  função, só troca o trigger) e é o único jeito de o usuário confirmar a feature sem
  esperar um ciclo real — mesmo padrão que o mac-metrics-view manteve mesmo depois de
  simplificar o toggle automático.

## Casos de borda

- Repo privado/rate-limited/offline no momento do check → R61 (falha silenciosa).
- Tag em formato inesperado (não numérico) → tratado como "sem update" (nunca crasha, nunca
  mostra versão inválida).
- `dismissedUpdateVersion` de build antigo sem a chave no JSON → `decodeIfPresent` cai no
  default `""` — string vazia nunca é "maior" que nada, então nunca mascara um update real.
- App aberto por dias sem restart (comportamento normal de menubar) → timer de 24h em
  `AppState` garante que o aviso apareça mesmo sem relaunch.
- **Quando Windows/Linux existirem** (Fase 2/3): `releases/latest` pode ser uma tag sem
  asset mac. Mitigar então checando se a release tem um asset com nome reconhecível de mac
  (ex. contém `.zip`/`mac`) antes de considerar "disponível" — não implementado agora, só
  existe 1 plataforma.

## Fora de escopo

| Item | Motivo |
| --- | --- |
| Auto-instalação / auto-download do update | Pedido foi "avisar", não instalar. Sparkle completo (mirror do mac-metrics-view) fica pra se/quando a Fase 4 do ROADMAP ("Auto-update por plataforma") for antecipada de verdade — decisão desta spec foi GitHub API + link manual. |
| Badge no ícone da menu bar | Usuário escolheu só label no popover. |
| Checar release Windows/Linux separadamente | Só existe app mac hoje — ver Casos de borda. |
| Autenticação na GitHub API | Endpoint público sem auth, 60 req/h por IP — folga enorme pra 1 check/24h. |
| Notificação de sistema (banner/som) fora do popover | Não pedido; label passivo já cobre "avisar". |

## Aceitação (UAT)

1. Instalação atual (1.0.0) contra o release real publicado (também 1.0.0) → sem aviso,
   nenhum rótulo aparece.
2. Simular versão mais nova (rodar com `CFBundleShortVersionString` de teste "0.9.0", ou
   apontar pra um repo/tag de teste) → rótulo "Nova versão x.x.x disponível" aparece com
   botão "Baixar".
3. Clicar "Baixar" → abre a página da release no navegador padrão (URL da release, não um
   asset direto).
4. Clicar "Ignorar esta versão" → rótulo some imediatamente; reabrir o popover (ou restart
   do app) → continua escondido enquanto a mesma tag for a mais nova.
5. Wi-Fi desligado → nenhum crash, nenhum erro visível, app funciona normalmente.
6. Botão "Verificar agora" (R62) força o ciclo sem esperar 24h.

## Decisões assumidas (fácil de mudar se incomodar)

- Repo hardcoded (`patrickonofre/cross-desk`) — não é config de usuário.
- "Baixar" abre a página HTML da release (`html_url`), não o asset `.zip` direto — usuário
  passa pela página (changelog, instruções de instalação/`xattr -cr`).
- Timer de 24h fixo a partir do launch (sem alinhamento a horário do dia) — simplicidade.
