# Context — release-1.0 (decisões do usuário)

Capturadas em 2026-07-07 via perguntas diretas antes do design/tasks.

## 1. Tags beta (já publicadas no GitHub)

**Decisão: deletar só as tags, local + remoto.** As 15 `v0.1.0-beta.1`..`v0.1.0-beta.15` somem (`git tag -d` + `git push origin --delete`); o histórico de 35 commits fica intacto (mensagens mencionando "beta" continuam visíveis no log). `v1.0.0` nasce no commit final da fase.

- Alternativa rejeitada: squash de todo o histórico num commit único — destrutivo demais (force-push, perde a narrativa de bugs/fixes documentada nos commits), não é o que "descartar as tags" pediu.
- Alternativa rejeitada: manter as tags beta ao lado de v1.0.0 — usuário quer a lista de tags/releases do GitHub começando limpa na 1.0.

## 2. Barra de qualidade para 1.0

**Decisão: 1.0 só fecha depois dos 5 UATs pendentes passarem.** Não é só "código completo" — é "verificado numa máquina real". Bloqueia a tag até:
- layout-ux (macOS T57)
- file-transfer E1 (macOS T47)
- input-polish (macOS T28)
- discovery-pairing (macOS T38)
- autostart (macOS T61)

- Alternativa rejeitada: tagear 1.0 já com o que está code-complete e tratar UAT como patch (1.0.1 etc.) — usuário quer 1.0 = estável de verdade.

## 3. Assinatura/distribuição

**Decisão: ad-hoc assinado (identidade "CrossDesk Dev" já usada em dev) + instruções de `xattr -cr` no README/Release notes.** Sem Apple Developer ID/notarização por ora.

- Alternativa rejeitada: notarização real — custo (~$99/ano) + tempo de revisão da Apple não justificam ainda pra esta fase.
- Alternativa rejeitada: release só de código-fonte sem binário — usuário quer um artefato baixável mesmo com a fricção do Gatekeeper.
- Pendência antiga ("conta Apple Developer necessária antes de distribuir", `macos/.specs/project/STATE.md`) continua registrada para revisitar depois — não é bloqueio da 1.0.

## 4. Licença

**Decisão: MIT.** Repo já é público; sem LICENSE = "todos os direitos reservados" por padrão no GitHub, o que não é a intenção.

- Alternativa rejeitada: GPL-3.0 (copyleft, mesma licença do Barrier) — usuário preferiu permissiva.
- Alternativa rejeitada: ficar sem licença por enquanto.

## Discricionariedade do agente

- Nome do produto ("CrossDesk") tratado como definitivo nesta fase — já é bundle id, nome do repo e ícone; não foi levantado como dúvida.
- Número de build (`CFBundleVersion`) continua incrementando (16 → 17); só o `CFBundleShortVersionString` marketing vira "1.0.0".
- CHANGELOG.md: incluído por padrão (formato Keep a Changelog) — custo baixo, valor alto para um repo público; não foi uma pergunta separada por ser decisão de baixo risco/reversível.

## Fora de escopo (fica pra depois)

- Apps Windows/Linux (Fase 2/3 do ROADMAP raiz).
- Apple Developer ID/notarização, dmg notarizado, auto-update (Fase 4).
- Drag-and-drop real de arquivo (file-transfer E2).
