# Tasks — release-1.0

Sem numeração `T` própria (feature raiz, cross-cutting) — referencia os `T#` do app mac onde aplicável.
Status: ☐ pendente · ◐ em progresso · ☑ feito.

## Fase 1 — Fechar qualidade (bloqueante, requer usuário + 2ª máquina)

- ☑ **Roteiro `UAT-1.0.md`** (RL5) — escrito 2026-07-07: 5 blocos (A–E) + setup unificado, absorve `UAT-2026-07-06.md`.
  - Where: `macos/.specs/project/UAT-1.0.md`
  - A EXECUÇÃO do roteiro (itens abaixo) continua manual/pendente.

- ☑ **UAT discovery-pairing** (RL4) — ✅ 2026-07-07, usuário reportou aceitações 1–8 ok. T38 fechado.
- ☑ **UAT file-transfer E1** (RL4) — ✅ 2026-07-07, usuário reportou aceitações 1,2,4,7,8 ok. T47 fechado.
- ☑ **UAT input-polish** (RL4) — ✅ 2026-07-07, usuário reportou ok. T28 fechado.
- ☑ **UAT layout-ux** (RL4) — ✅ 2026-07-07, usuário reportou R35–R41 ok. T57 fechado.
- ☑ **UAT autostart** (RL4) — ✅ 2026-07-07, usuário reportou as 6 ok, incl. restart real. T61 fechado.
- ☑ **Corrigir bugs achados** — nenhum bug reportado nesta sessão.

Gate da Fase 1: **fechado 2026-07-07** (usuário reportou os 5 blocos passando, sem bugs — ver `macos/.specs/project/STATE.md`).

## Fase 2 — Versão e build `[P]` com Fase 3

- ☑ **Bump de versão** (RL7) — `CFBundleShortVersionString` → `1.0.0`, `CFBundleVersion` → `17` em `Scripts/make-app.sh`.
- ☑ **Build universal final** (RL6) — `UNIVERSAL=1 Scripts/make-app.sh`, arm64+x86_64, "CrossDesk Dev". 177 testes verdes, build sem warnings. Zip em `macos/build/CrossDesk.zip` (1.3M).

## Fase 3 — Documentação e repo `[P]` com Fase 1

- ☑ **`LICENSE`** (RL2) — MIT, copyright Patrick Onofre, 2026. Raiz do repo.
- ☑ **`CHANGELOG.md`** (RL3) — formato Keep a Changelog. `[1.0.0] - 2026-07-07`.
- ☑ **README raiz atualizado** (RL8) — seção "Instalação" (`xattr -cr`), link LICENSE/CHANGELOG, status "1.0 — macOS estável".

## Fase 4 — Higiene de tags (depende de Fase 1+2 fechadas)

- ☐ **Deletar as 15 tags beta, local** (RL1)
  - `for t in $(git tag -l 'v0.1.0-beta.*'); do git tag -d "$t"; done`
- ☐ **Deletar as 15 tags beta, remoto** (RL1) — ação em GitHub público, confirmar antes de rodar
  - `git push origin --delete $(git tag -l 'v0.1.0-beta.*')` (ou uma de-cada-vez)

## Fase 5 — Publicação (depende de todas as fases acima)

- ☐ **Tag `v1.0.0`** (RL9) — anotada, no commit final (build bump + docs), local + remoto.
- ☐ **GitHub Release "v1.0.0"** (RL10) — `gh release create v1.0.0`, notas = resumo do CHANGELOG, zip do build universal anexado. Ação pública — confirmar antes de publicar.

## Aceitação final

Ver `spec.md` §Aceitação (7 itens) — todos verdes fecha a feature.
