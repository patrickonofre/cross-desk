# Tasks — Site de produto CrossDesk

## T1 — Extrair design system base [P]
**What:** copiar tokens de `mac-metrics-view/docs/styles.css` (`:root`, dark mode, tipografia, `--radius`/`--shadow`, estilo de botão/card) pra novo `docs/styles.css` neste repo. Ajustar nome de fonte/comentários se referenciarem "Mac Metrics View".
**Where:** `cross-desk/docs/styles.css`.
**Depends on:** nada.
**Reuses:** `mac-metrics-view/docs/styles.css` linhas 1-~120 (tokens + base).
**Done when:** arquivo existe, sem referência a mac-metrics-view no conteúdo.
**Tests:** visual (preview).
**Gate:** nenhum automatizado ainda (roda junto com T7).

## T2 — Estrutura HTML (PT) [depends: T1]
**What:** criar `docs/index.html` com as 9 seções do design.md (topbar, hero, como-funciona, features, privacidade, instalação, download, timeline, footer), conteúdo real do README/CHANGELOG, `data-i18n` em todo texto.
**Where:** `cross-desk/docs/index.html`.
**Depends on:** T1.
**Reuses:** estrutura de `mac-metrics-view/docs/index.html` (tags semânticas, `aria-label`, `scroll-margin-top`).
**Done when:** página renderiza todas as 9 seções, sem `console.error`.
**Tests:** preview screenshot light/dark/mobile.
**Gate:** —

## T3 — Diagrama SVG "como funciona" [depends: T2]
**What:** SVG inline (2 telas + seta + cursor) conforme design.md, usando variáveis CSS do design system.
**Where:** dentro de `docs/index.html`, seção "Como funciona".
**Depends on:** T2.
**Done when:** diagrama visível em light e dark mode, sem asset binário externo.
**Tests:** preview visual.

## T4 — i18n: `i18n.js` + `en/index.html` [depends: T2]
**What:** gerar dicionário `i18n.js` com todas as chaves `data-i18n` de T2 (PT + EN), e página gêmea `docs/en/index.html`.
**Where:** `cross-desk/docs/i18n.js`, `cross-desk/docs/en/index.html`.
**Depends on:** T2.
**Reuses:** padrão de `mac-metrics-view/docs/i18n.js` e `scripts/build-en-page.mjs` (adaptar script ou gerar manualmente, o que for mais rápido pro volume de texto deste site).
**Done when:** toggle PT↔EN troca todo texto, nenhuma chave órfã.
**Tests:** `node scripts/check-i18n-parity.mjs` (ver T7).

## T5 — SEO: sitemap/robots/JSON-LD/meta [depends: T2, T4]
**What:** `sitemap.xml`, `robots.txt`, meta tags (title/description/OG), JSON-LD `SoftwareApplication` (versão 1.2.1, MIT, macOS).
**Where:** `cross-desk/docs/sitemap.xml`, `cross-desk/docs/robots.txt`, dentro de `index.html`/`en/index.html`.
**Depends on:** T2, T4.
**Done when:** JSON-LD parseia sem erro (validar com `JSON.parse` no preview console).

## T6 — Nav cruzada (hub + Mac Metrics View) [depends: T2, T4]
**What:** links no topbar/footer pro hub (`patrickonofre.github.io`) e Mac Metrics View (`patrickonofre.github.io/mac-metrics-view/`).
**Where:** `docs/index.html`, `docs/en/index.html`.
**Depends on:** T2, T4.
**Done when:** os 2 links resolvem (checar manualmente — hub só existe depois de `hub-landing` publicado, ok linkar antes do hub estar no ar).

## T7 — Gates automatizados [depends: T4]
**What:** adaptar `check-i18n-parity.mjs` e `check-site-assets.mjs` de mac-metrics-view pros paths/manifest deste repo.
**Where:** `cross-desk/scripts/check-i18n-parity.mjs`, `cross-desk/scripts/check-site-assets.mjs`.
**Depends on:** T4.
**Reuses:** `mac-metrics-view/scripts/check-i18n-parity.mjs`, `mac-metrics-view/scripts/check-site-assets.mjs`.
**Done when:** ambos rodam com exit 0 contra o conteúdo de T2-T6.

## T8 — Validação final (UAT)
**What:** preview completo — console limpo, screenshot light/dark/mobile, toggle PT/EN, link de download resolve pro GitHub Releases real, confirmar `docs/appcast.xml` segue idêntico (diff vazio) e Sparkle não foi afetado.
**Depends on:** T3, T5, T6, T7.
**Done when:** todos os gates do spec.md (R1-R9) passam.

## Paralelização

- T1 pode rodar sozinho antes do resto.
- T2 depende só de T1; T3/T4/T5/T6 podem ser feitas em sequência ou por diferentes sub-agentes desde que T2 já exista (T3-T6 tocam a mesma página, então sequencial é mais seguro que paralelo aqui pra evitar conflito de edição).
- T7 só depois do texto estabilizar (T4).
- T8 é gate final, depende de tudo.
