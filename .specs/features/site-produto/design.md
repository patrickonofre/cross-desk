# Design — Site de produto CrossDesk

## Arquitetura

Réplica do padrão já validado em `mac-metrics-view/docs/`: HTML/CSS/JS estático, sem build tool, i18n via par de páginas (`index.html` PT + `en/index.html` EN) com dicionário `data-i18n` em `i18n.js`, gates via scripts Node standalone (`check-i18n-parity.mjs`, `check-site-assets.mjs`).

Diferença estrutural principal: **sem seção "demo" interativa** (mac-metrics-view tem tabs de popover ao vivo; CrossDesk não tem UI de popover equivalente pronta pra reproduzir em HTML/CSS) — substituída por diagrama estático (SVG inline) ilustrando o conceito de cursor cruzando de servidor pra cliente.

## Estrutura de arquivos

```
cross-desk/
├── docs/
│   ├── index.html          (PT, novo)
│   ├── en/index.html       (EN, novo)
│   ├── styles.css          (novo, tokens copiados de mac-metrics-view + ajustes)
│   ├── i18n.js             (novo)
│   ├── sitemap.xml         (novo)
│   ├── robots.txt          (novo)
│   ├── appcast.xml         (existente, NÃO TOCAR)
│   └── assets/
│       ├── app-icon.png    (exportado do AppIcon.icns existente)
│       └── diagram-*.svg   (ilustrações placeholder, geradas inline/SVG — sem asset binário externo)
└── scripts/
    ├── check-i18n-parity.mjs   (adaptado de mac-metrics-view/scripts/)
    └── check-site-assets.mjs   (adaptado, manifest próprio)
```

## Seções (ordem final)

1. **Topbar**: logo/nome CrossDesk + nav (Como funciona / Features / Instalação / Download) + links cruzados (hub, Mac Metrics View) + toggle PT/EN.
2. **Hero**: título + subtítulo + CTA "Baixar" (→ GitHub Releases) + selo "1.0 · macOS · Open Source (MIT)".
3. **Como funciona**: diagrama SVG (2 telas lado a lado, cursor cruzando a borda) + 3 passos em texto (servidor escolhe borda → cliente informa código → cursor cruza).
4. **Features**: grid de cards — Latência (UDP), Segurança (DTLS-PSK), Pareamento (código curto), Esc×3 (failsafe), Autostart, Auto-update, Clipboard de arquivos.
5. **Privacidade/Segurança**: bullet list — sem telemetria, sem conta, protocolo documentado publicamente (link pro `PROTOCOL.md` no repo), criptografia por padrão.
6. **Instalação**: passo a passo real (baixar → mover pra Aplicativos → `xattr -cr` se necessário → permissões de Acessibilidade/Monitoramento de Entrada) — honesto sobre falta de notarização.
7. **Download**: botão → `github.com/patrickonofre/cross-desk/releases/latest`, nota "macOS 14+".
8. **Roadmap/Timeline**: baseado no CHANGELOG real, dos releases 1.0.0 até 1.2.1, com nota "Windows e Linux em fases futuras".
9. **Footer**: MIT, link repo, links cruzados (hub, Mac Metrics View).

## Reuso de design system

Tokens extraídos de `mac-metrics-view/docs/styles.css` linhas 1-40 (`:root`, `@media (prefers-color-scheme: dark)`): `--bg`, `--bg-alt`, `--surface`, `--text`, `--muted`, `--line`, `--accent`, `--radius`, `--shadow`, gradiente de h1. Copiados 1:1 — paleta é neutra o suficiente pra servir os 2 produtos sem parecer reskin malfeito.

## Placeholders visuais (R4 do spec)

Em vez de screenshot: SVG simples, 2 retângulos representando telas (rótulo "Servidor" / "Cliente"), seta pontilhada cruzando a borda entre eles, ícone de cursor na ponta da seta. Estilo flat, usa as mesmas cores do design system (`--accent`, `--line`) — não é arte finalizada, é diagrama funcional. Pendência registrada no STATE.md do hub pra troca futura por screenshot real.

## Gates adaptados

- `check-i18n-parity.mjs`: mesma lógica (contar chaves `data-i18n` em PT vs EN, todas referenciadas em `i18n.js`), só troca os paths de `docs/index.html`/`docs/en/index.html` deste repo.
- `check-site-assets.mjs`: manifest próprio (sem os PNGs de popover do mac-metrics-view — aqui são só SVGs inline + 1 PNG de ícone).
