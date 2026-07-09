# Spec — Site de produto CrossDesk

**Scope:** Large. Files: `docs/index.html`, `docs/en/index.html`, `docs/styles.css`, `docs/i18n.js`, `docs/sitemap.xml`, `docs/robots.txt`, `docs/assets/*` (ilustrações placeholder), `scripts/check-i18n-parity.mjs`, `scripts/check-site-assets.mjs` (novos, adaptados de mac-metrics-view). `docs/appcast.xml` **não muda**.
**Goal:** site de produto completo pro CrossDesk em `https://patrickonofre.github.io/cross-desk/`, no mesmo padrão visual/técnico do site do Mac Metrics View (Apple-grade, PT+EN, sem telemetria), com conteúdo real (o produto já existe e está em 1.0) mas **sem screenshots reais** — ilustrações/diagramas no lugar (decisão do usuário: lançar com placeholder, trocar depois).

## Contexto de produto (fonte: README.md, CHANGELOG.md, .specs/project/{PROJECT,ROADMAP,STATE}.md)

- CrossDesk = KVM por software (compartilha teclado/mouse via rede, sem vídeo) — sucessor espiritual do Barrier (morto desde 2021).
- Modelo servidor/cliente: 1 Mac dono do teclado/mouse (servidor), os demais (clientes) recebem controle quando o cursor cruza a borda da tela.
- Diferenciais reais (não são promessa, já implementados): transporte UDP (sem head-of-line blocking do TCP usado por Synergy/Barrier), criptografia DTLS-PSK (sem modo texto-plano), pareamento por código curto (`XXX-XXX`, 6 chars), Esc×3 sempre devolve controle ao servidor mesmo com rede caída, autostart via `SMAppService`, auto-update real via Sparkle (v1.2.1, EdDSA), clipboard de arquivos (⌘C/⌘V) entre máquinas.
- Status: 1.0 estável mac↔mac. Windows/Linux nas próximas fases (não vender como pronto).
- Distribuição: **não notarizado** ainda (sem conta Apple Developer) — instalação exige `xattr -cr` no `.app` baixado. Isso precisa aparecer no site (seção de instalação), não esconder.
- Licença: MIT, repo público.

## Requirements

- **R1 — Estrutura de seções**, adaptada do padrão mac-metrics-view (`docs/index.html` de referência) pro contexto de KVM:
  - Hero: nome + proposta ("Compartilhe teclado e mouse entre Macs pela rede, sem vídeo").
  - Como funciona: diagrama ilustrado (SVG placeholder) mostrando cursor cruzando de um Mac servidor pra um Mac cliente.
  - Features: cards pros diferenciais reais listados acima (UDP/latência, criptografia, pareamento, Esc×3, autostart, auto-update, clipboard de arquivos).
  - Privacidade/segurança: seção dedicada (DTLS-PSK, sem telemetria, sem conta, protocolo aberto documentado).
  - Instalação: passo a passo real, incluindo o aviso de `xattr -cr` (não escamotear a falta de notarização).
  - Download: botão pra `https://github.com/patrickonofre/cross-desk/releases/latest` (não pra `docs/downloads/` — distribuição do CrossDesk é via GitHub Releases, diferente do mac-metrics-view).
  - Roadmap/timeline: baseado no CHANGELOG.md real (1.0.0 → 1.2.1), deixando claro que Windows/Linux vêm depois.
  - Footer: link MIT license, link pro repo, nav cruzado pro hub e pro Mac Metrics View.
- **R2 — Design system compartilhado.** `docs/styles.css` reusa os tokens de `mac-metrics-view/docs/styles.css` (`:root`, dark mode, `--radius`/`--shadow`, tipografia) — cópia adaptada, não import cross-repo.
- **R3 — i18n PT/EN.** Mesmo mecanismo do mac-metrics-view: `docs/index.html` (PT, default) + `docs/en/index.html` (EN) + `docs/i18n.js` com `data-i18n`. PT é o idioma default do produto (README já é PT).
- **R4 — Ilustrações placeholder, não screenshot.** Nenhuma captura de UI real na v1 (produto não tem fluxo de captura ainda — ver Pendência no STATE.md do hub). Usar SVG/diagrama ilustrativo pro "como funciona" e pros cards de feature. Trocar por screenshot real fica registrado como pendência aberta.
- **R5 — SEO básico.** `<title>`, meta description, OG, JSON-LD `SoftwareApplication` (nome, versão 1.2.1, `operatingSystem: macOS`, `license: MIT`), `sitemap.xml`, `robots.txt` — mesmo padrão do mac-metrics-view.
- **R6 — Gates de qualidade.** Adaptar `scripts/check-i18n-parity.mjs` e `scripts/check-site-assets.mjs` de mac-metrics-view pro repo cross-desk (paths/manifest próprios).
- **R7 — Honestidade sobre maturidade.** Não posicionar como "pronto pra todo mundo" — deixar claro: 1.0 estável só mac↔mac, sem notarização ainda, Windows/Linux futuro. Consistente com README/CHANGELOG reais.
- **R8 — Nav cruzada.** Link pro hub (`patrickonofre.github.io`) e pro Mac Metrics View (`patrickonofre.github.io/mac-metrics-view/`) no topbar/footer — espelha [hub-nav-links](../../../mac-metrics-view/.specs/features/hub-nav-links/spec.md) do outro repo.
- **R9 — `docs/appcast.xml` intocado.** Nenhuma mudança de path, conteúdo ou comentário existente nesse arquivo.

## Gates

- `node scripts/check-i18n-parity.mjs` → exit 0
- `node scripts/check-site-assets.mjs` → exit 0
- JSON-LD parseia sem erro.
- Preview: console limpo, screenshot light+dark+mobile, toggle PT↔EN funcional, link de download resolve pro GitHub Releases real, `docs/appcast.xml` continua servindo idêntico ao de antes.

## Non-goals

- Screenshot/captura de UI real (adiado — precisa de fluxo de captura próprio, feature separada).
- Suporte Windows/Linux no conteúdo do site (não existe ainda — não prometer).
- Domínio próprio, analytics.

## Validation (2026-07-09)

- R1-R9 implementados. Arquivos: `docs/index.html`, `docs/en/index.html`, `docs/styles.css`, `docs/i18n.js`, `docs/site.js`, `docs/sitemap.xml`, `docs/robots.txt`, `docs/assets/app-icon.png`, `scripts/check-i18n-parity.mjs`, `scripts/check-site-assets.mjs`, `scripts/site-assets-manifest.json`.
- Gates: `check-i18n-parity.mjs` ✓ (75 pt = 75 en, todas referenciadas); `check-site-assets.mjs` ✓ (ícone presente, PNG válido, dentro do budget).
- Preview: console limpo em ambas as páginas; dark/light/mobile conferidos; diagrama SVG "como funciona" renderiza nos dois temas; toggle PT→EN navega e traduz corretamente; link de download aponta pro GitHub Releases real; `docs/appcast.xml` confirmado intocado (`git status` vazio nesse arquivo).
- Achado durante validação: nav com 5 itens + 2 links cruzados + lang-switch quebrava linha em larguras médias — corrigido escondendo `.nav-cross` abaixo de 1150px (o cross-link continua garantido pelo footer, que não tem esse limite).
- Correção pós-review do usuário (2026-07-09): removidas todas as menções a concorrentes (Barrier/Synergy) do conteúdo do site — meta description, `features.title`/`features.udpBody` (pt/en) reescritos sem citar nomes de produto de terceiros. Mantido apenas no `README.md` do repo (contexto técnico interno, não é conteúdo do site).
