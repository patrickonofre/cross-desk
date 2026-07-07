# Spec — release-1.0 (primeira versão pública no GitHub)

**Escopo:** Large (multi-componente: higiene de git/tags, licenciamento, 5 UATs pendentes, empacotamento, GitHub Release — cross-cutting, não é só código do app mac). Pipeline completo: spec → context (✅ `context.md`) → tasks → execute.

**Contexto:** o repo (`patrickonofre/cross-desk`) já é público no GitHub desde 2026-07-03, com as 15 tags `v0.1.0-beta.*` já publicadas junto com todo o histórico de desenvolvimento (35 commits). O Fase 1 (app macOS, ver [ROADMAP raiz](../../project/ROADMAP.md)) está com o código de todas as features MVP+pós-MVP completo, mas 5 delas ainda não passaram por UAT numa máquina real. Esta feature fecha essa fase com uma versão 1.0 de verdade: tags beta descartadas, UATs verificados, licença definida, release publicada.

## Requisitos

### A. Higiene de repositório

- **RL1** — Deletar as 15 tags `v0.1.0-beta.1`..`v0.1.0-beta.15`, local e remoto (`git tag -d` + `git push origin --refs/tags/...` delete). Histórico de commits permanece intocado.
- **RL2** — `LICENSE` (MIT) na raiz do repo, copyright do usuário, ano 2026.
- **RL3** — `CHANGELOG.md` na raiz (formato [Keep a Changelog](https://keepachangelog.com)), entrada `[1.0.0]` resumindo as features da Fase 1 (KVM mac↔mac, discovery+pairing, file-transfer E1, input-polish/conceal, layout-ux, autostart).

### B. Fechamento de qualidade (bloqueante — gate da tag 1.0)

- **RL4** — Rodar e fechar os 5 UATs pendentes, todas as aceitações dos respectivos specs verdes (ou desvio documentado em `macos/.specs/project/STATE.md`, mesmo padrão já usado no projeto):
  - layout-ux — `macos/.specs/features/layout-ux/tasks.md` T57
  - file-transfer E1 — `macos/.specs/features/file-transfer/tasks.md` T47
  - input-polish — `macos/.specs/features/input-polish/tasks.md` T28
  - discovery-pairing — `macos/.specs/features/discovery-pairing/tasks.md` T38
  - autostart — `macos/.specs/features/autostart/tasks.md` T61
- **RL5** — Roteiro de UAT consolidado (novo `macos/.specs/project/UAT-1.0.md`, nos moldes de `UAT-2026-07-06.md`) cobrindo os 5 blocos acima numa sessão de 2 Macs, incluindo o restart real que o autostart exige (aceitação 5 do spec de autostart).

### C. Empacotamento e distribuição

- **RL6** — Build universal (`UNIVERSAL=1 Scripts/make-app.sh`, arm64+x86_64), assinado com a identidade "CrossDesk Dev" (ad-hoc do ponto de vista de terceiros — sem Apple Developer ID).
- **RL7** — `CFBundleShortVersionString` → `"1.0.0"` em `Scripts/make-app.sh`. `CFBundleVersion` (build number) segue a contagem incremental normal (16 → 17+, não reseta).
- **RL8** — README raiz ganha seção "Instalação" cobrindo o download do zip + `xattr -cr CrossDesk.app` (documenta o mesmo problema de App Translocation já achado no UAT de 2026-07-06) + status atualizado ("1.0 — macOS estável" em vez de "MVP em validação").

### D. Publicação

- **RL9** — Tag `v1.0.0` (anotada) no commit final da fase, local + remoto.
- **RL10** — GitHub Release "v1.0.0" via `gh release create`, notas = resumo do CHANGELOG + link de instalação, zip do build universal anexado como asset.

## Fora de escopo (1.0)

| Item | Motivo |
| --- | --- |
| Apps Windows/Linux | Fase 2/3 do ROADMAP raiz — 1.0 é só macOS↔macOS. |
| Apple Developer ID / notarização / dmg notarizado | Decisão explícita (context.md #3): ad-hoc + `xattr -cr` documentado é suficiente por ora. Pendência antiga continua registrada em `macos/.specs/project/STATE.md` para revisitar. |
| Auto-update | Fase 4 do ROADMAP raiz. |
| Drag-and-drop real de arquivo (file-transfer E2) | Já fora de escopo do MVP de file-transfer; não bloqueia 1.0. |
| Renomear o produto | "CrossDesk" tratado como definitivo (bundle id, repo e ícone já usam) — ver context.md. |
| ADRs de stack Windows/Linux | Só na abertura das fases 2/3 (pendência já registrada). |

## Aceitação

1. `git tag -l` local e `git ls-remote --tags origin` **não** mostram mais nenhuma `v0.1.0-beta.*`.
2. `v1.0.0` existe local e remoto, apontando pro commit final da fase (build universal, versão 1.0.0 no Info.plist).
3. `LICENSE` (MIT) e `CHANGELOG.md` presentes na raiz; README referencia os dois.
4. 5/5 UATs pendentes com todas as aceitações verificadas (roteiro `UAT-1.0.md` fechado) — qualquer bug achado ao vivo é corrigido antes da tag (mesmo padrão de toda sessão de UAT anterior do projeto).
5. `swift test` verde (177+ testes) e `make-app.sh` (`UNIVERSAL=1`) sem warnings no commit taggeado.
6. GitHub Release "v1.0.0" publicada e visível em `github.com/patrickonofre/cross-desk/releases`, com o zip anexado.
7. README raiz não menciona mais "MVP em validação" nem tags beta.

## Decisões assumidas (ver context.md para o que foi perguntado)

- Build number continua a contagem existente (não reseta em 1.0).
- CHANGELOG.md incluído por padrão — decisão de baixo risco, não fez parte das perguntas.
