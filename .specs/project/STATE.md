# STATE — CrossDesk (raiz)

## Decisões

- **2026-07-03 — ADR-002: apps nativas separadas por OS** (decisão do usuário, supera ADR-001/Rust). macOS primeiro, Swift 100% nativo, pasta `macos/`. Protocolo neutro versionado + golden vectors como contrato entre apps. Racional em [TECH-DECISION.md](TECH-DECISION.md).
- **2026-07-03 — Protocolo próprio**, sem compatibilidade Synergy/Barrier na v1.
- **2026-07-03 — Keycodes em USB HID Usage IDs** no fio (neutro entre CGKeyCode/scancode/evdev).
- **2026-07-03 — Geometria independente por máquina** (protocolo §5): resolução/layout nunca trafegam; cliente detecta a própria borda de retorno (LEAVE_REQUEST 0x12). Vale para todas as implementações (Windows/Linux herdam o contrato).

- **2026-07-04 — file-transfer antecipada** (decisão do usuário; era "ideia adiada"/não-objetivo v1). Staged: E1 clipboard de arquivos (⌘C/⌘V, API pública), E2 drag real só se spike S1 provar (Synergy falhou nisso; Deskflow removeu). Destino fallback: `~/Downloads/CrossDesk/`. Specs: `macos/.specs/features/file-transfer/`.
- **2026-07-05 — PROTOCOL.md §2 ganhou regra normativa de truncagem de campos `utf8`** (achado em code review profundo da app mac): cortar string longa por contagem de bytes crus pode partir um escalar Unicode ao meio, e o receptor descarta a mensagem inteira como corrompida. Vale para toda implementação (Windows/Linux herdam a regra) — ver Changelog do protocolo e `macos/.specs/project/STATE.md` (lições) para o detalhe técnico e o fix de referência (`WireStrings.utf8Prefix`).
- **2026-07-06 — token curto de pareamento reduzido de 8 para 6 chars** (decisão do usuário; PROTOCOL.md §1, `XXXX-XXXX` → `XXX-XXX`, ≈39 → ≈29 bits). Troca deliberada de UX (menos dígitos pra ler/digitar) por menos entropia; aceitável porque o token nunca trafega no fio (deriva PSK localmente nos dois lados) e é substituído pelo segredo rotacionado de 128 bits logo no 1º handshake (R29) — a única janela de exposição é o handshake de pareamento em si, já documentada. Sem mudança de formato de fio nem golden vectors. Vale para toda implementação (Windows/Linux herdam a regra).
- **2026-07-07 — release-1.0 especificada** (repo já é público em `github.com/patrickonofre/cross-desk` desde 2026-07-03, com as 15 tags `v0.1.0-beta.*` já publicadas). Decisões do usuário (ver `.specs/features/release-1.0/context.md`): (1) descartar só as tags beta local+remoto, histórico de commits intacto; (2) 1.0 só fecha depois dos 5 UATs pendentes passarem (discovery-pairing T38, file-transfer T47, input-polish T28, layout-ux T57, autostart T61 — todos em `macos/.specs/`); (3) distribuição ad-hoc assinado + `xattr -cr` documentado, sem Apple Developer ID por ora; (4) licença MIT. Spec+tasks em `.specs/features/release-1.0/`.
- **2026-07-07 — CrossDesk 1.0.0 publicado**: os 5 UATs fechados (usuário reportou passando, sem bugs — ver `macos/.specs/project/STATE.md`), versão bumpada (`CFBundleShortVersionString` 1.0.0, build 17), `LICENSE`/`CHANGELOG.md`/README prontos, as 15 tags `v0.1.0-beta.*` deletadas (local+remoto — `git ls-remote --tags origin` só mostra `v1.0.0`), tag anotada `v1.0.0` e [GitHub Release](https://github.com/patrickonofre/cross-desk/releases/tag/v1.0.0) publicados com o build universal (`CrossDesk.zip`) anexado. Commits: `8b4a71f` (autostart), `f21390c` (docs/UATs), `74e1b02` (LICENSE/CHANGELOG/README), `bf1936a` (bump versão). **Fase 1 do ROADMAP (app macOS) fechada.**

## Bloqueios

- Nenhum.

## Pendências

- [x] ~~release-1.0~~ — **CONCLUÍDA 2026-07-07**, ver decisão acima. `v1.0.0` publicado no GitHub.
- [ ] Conta Apple Developer (signing/notarização) — necessária antes de distribuir a app mac; dev local funciona com assinatura ad-hoc estável. **Não bloqueia a 1.0** (decisão 2026-07-07: ad-hoc + `xattr -cr` documentado é suficiente por ora).
- [ ] Definir nome final do produto (working title: CrossDesk) — `release-1.0/spec.md` assume "CrossDesk" como definitivo por já estar no bundle id/repo/ícone; revisar se o usuário discordar.
- [ ] ADRs de stack para Windows e Linux (na abertura das fases 2 e 3).

## Lições

- CGEventTap no macOS é silenciosamente desabilitado se a assinatura do binário mudar entre builds — signing estável desde o dev local.

## Preferences

- Usuário fala português; respostas em modo caveman ultra (skill /caveman).
- Trabalho por app na pasta da app (`macos/.specs/`); raiz guarda visão, protocolo e decisões cross-app.
