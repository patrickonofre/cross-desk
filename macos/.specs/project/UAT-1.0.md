# Roteiro UAT — release 1.0 (sessão única, 2 Macs)

Consolida os 5 UATs pendentes do Fase 1 antes de tagear `v1.0.0` (ver [`.specs/features/release-1.0/`](../../../.specs/features/release-1.0/spec.md)): **T38** (discovery-pairing), **T47** (file-transfer E1), **T28** (input-polish), **T57** (layout-ux), **T61** (autostart). Blocos A/B/C vêm de [`UAT-2026-07-06.md`](UAT-2026-07-06.md) (atualizados aqui — números de teste, etc.); D/E são novos.

**Ordem pensada para minimizar retrabalho:** parear (A) → arquivos (B) → sleep/wake (C) → layout-ux visual (D) → autostart/restart (E, **por último** — é o único bloco que mexe no estado de boot do sistema).

**Convenção:** SRV = mac servidor (teclado/mouse físicos), CLI = mac cliente. Marcar ✅/❌ + observação em cada item; ao final, sintetizar em `STATE.md` e fechar os `T#` correspondentes nos respectivos `tasks.md`.

## 0. Setup

- [ ] Build universal novo: `cd macos/CrossDeskKit && swift test` (baseline 177 verdes) → `UNIVERSAL=1 macos/Scripts/make-app.sh`.
- [ ] Distribuir `macos/build/CrossDesk.app` para a outra máquina (zip → AirDrop/ssh). No destino: `xattr -cr /caminho/CrossDesk.app`.
- [ ] TCC: SRV precisa **Monitoramento de Entrada**; CLI precisa **Acessibilidade**. Toggle aparece ligado mas falha: `tccutil reset All dev.crossdesk.mac` + conceder de novo.
- [ ] Config limpa para testar pareamento do zero: apagar `~/Library/Application Support/CrossDesk/config.json` nas DUAS máquinas.
- [ ] Mesma LAN, mDNS funcionando.

## A. discovery-pairing (T38, aceitações 1–8 do spec)

- [ ] **A1 visibilidade:** SRV inicia como servidor → aparece na lista do CLI em ≤3 s. SRV para → some da lista em ≤10 s.
- [ ] **A2 pareamento feliz:** CLI toca "Parear…", digita o token exibido no SRV → conecta; selo "Pareado" nos dois lados.
- [ ] **A3 token errado:** digitar token inválido → erro claro no CLI (timeout de handshake), sem travar; corrigir e conectar.
- [ ] **A4 rotação persistida:** após A2, `config.json` dos DOIS lados tem `pairedSecret` (32 hex). Reiniciar os dois apps → reconexão silenciosa SEM digitar token (fingerprint igual nos logs).
- [ ] **A5 esquecer no servidor:** SRV "Esquecer pareamento" → token novo exibido; CLI tenta conectar → falha com o segredo antigo e cai para pedir token; parear de novo com o token novo.
- [ ] **A6 esquecer no cliente:** CLI "Esquecer" → volta à lista; parear de novo.
- [ ] **A7 Rede Local negada→concedida:** revogar Rede Local do CLI (Ajustes → Privacidade → Rede Local) → lista vazia + aviso laranja aparece; conceder de volta → lista volta sem reiniciar o app (se precisar reiniciar, registrar).
- [ ] **A8 fallback IP:** com descoberta funcionando, conectar mesmo assim por "Conectar por IP…" usando endereço mostrado no painel do SRV → funciona igual.

## B. file-transfer E1 (T47, aceitações 1, 2, 4, 7, 8)

Pré: pareado e conectado (bloco A). Cursor pode estar em qualquer máquina; ⌘C/⌘V normais.

- [ ] **B1a pequeno SRV→CLI:** copiar (⌘C) um arquivo pequeno no Finder do SRV → painel do CLI mostra "Recebendo/Arquivos prontos" → ⌘V numa pasta do Finder do CLI → arquivo íntegro (abrir).
- [ ] **B1b pequeno CLI→SRV:** mesmo caminho inverso.
- [ ] **B2 grande (≥1 GB):** `mkfile -n 1g /tmp/teste-1gb.bin` no SRV. Copiar → CLI mostra **oferta pendente** (>200 MB) → tocar "Receber" → progresso avança → termina em `~/Downloads/CrossDesk/` + Finder revela. Repetir e tocar **Cancelar** no meio → sem arquivo parcial em Downloads nem staging (`~/Library/Caches/CrossDesk/incoming/` limpo).
- [ ] **B4 rede caída no meio:** iniciar transferência do 1 GB → desligar Wi-Fi do SRV no meio → CLI mostra falha limpa, sem parcial visível; religar Wi-Fi → input reconecta sozinho; nova transferência funciona.
- [ ] **B7 input fluido durante transferência:** durante o 1 GB, mover mouse/digitar na máquina remota → sem stutter perceptível.
- [ ] **B8 build antigo:** se houver build anterior guardado, rodar num lado e build novo no outro → input funciona, transferência simplesmente não acontece, sem crash/log de erro em loop.

## C. input-polish (T28)

- [ ] **C1 invisibilidade:** com cursor no CLI, a seta do SRV some de verdade. Voltar → seta reaparece no ponto certo. Inverso também.
- [ ] **C2 matriz standby/wake:** com trava ativa, `pmset displaysleepnow` em cada máquina → acordar → trava/ocultação continuam. Repetir com screensaver e troca de resolução/monitor se disponível.
- [ ] **C4 scroll/momentum:** trackpad no SRV controlando CLI: Safari/Xcode fazem rubber-band/inércia natural.
- [ ] **C5 autorepeat + modificadores:** segurar tecla (repete no CLI), atalhos ⌘C/⌘Tab/⇧ funcionam; Esc 3× SEMPRE devolve o controle (inclusive com rede caída).
- [ ] **C7 latência p95:** ler p95 captura→injeção das métricas (`logSummary` no stop) → registrar número.
- [ ] **C8 regressão kvm-mvp:** travessia de borda nas duas direções, clique, drag de janela, borda de retorno.

## D. layout-ux (T57 — R35–R41)

- [ ] **D1 mini-mapa (R35):** conectar e mover cursor pro Mac remoto → ponto de foco muda no mini-mapa em <1s; parar sessão → mapa esvazia.
- [ ] **D2 janela Telas (R36):** abrir via clique no mini-mapa; com 2 monitores físicos, canvas reflete disposição real; desconectar um monitor → canvas atualiza sem reabrir a janela.
- [ ] **D3 arrastar define borda (R37):** no SRV, arrastar tile do peer da direita pra cima → `edgeSide` vira `.top`, sessão reiniciada usa a nova borda; picker de enum e canvas nunca divergem. No CLI, tile do servidor é só-leitura na borda de retorno.
- [ ] **D4 estados vivos (R38):** percorrer stopped → waitingPeer (pareando) → waitingPeer (pareado) → connected → controllingRemote → transferência ativa → error (forçar um erro) — cada transição muda o visual em <1s.
- [ ] **D5 microcopy de travessia (R39):** logo após parear pela 1ª vez, dica direcional aparece; some após a 1ª travessia; não reaparece nem depois de restart.
- [ ] **D6 acessibilidade (R40):** VoiceOver ligado, ler estado/borda sem tocar no canvas; trocar borda 100% via teclado.
- [ ] **D7 ícone do menubar (R41):** ícone muda em `controllingRemote`, volta em LOCAL/parado.

## E. autostart (T61 — por último, mexe em restart/logout)

- [ ] **E1:** instalação "nova" (config limpo já feito no Setup) → toggle "Abrir ao iniciar sessão" aparece desligado.
- [ ] **E2:** ligar o toggle → entrada aparece em Ajustes do Sistema > Geral > Itens de Login (habilitada ou pendente).
- [ ] **E3:** se pendente, botão "Abrir Ajustes" leva direto ao painel certo; aprovar → toggle da app reflete "ligado" em até 2s.
- [ ] **E4:** desligar o toggle → entrada some de Itens de Login.
- [ ] **E5 (restart real):** ligar o toggle de novo → reiniciar o Mac (ou logout/login) → CrossDesk abre sozinho no menubar sem intervenção.
- [ ] **E6:** desabilitar a entrada direto em Ajustes (sem tocar no app) → reabrir o painel do CrossDesk → toggle reflete "desligado" em até 2s.

## Registro

**2026-07-07 — usuário rodou a sessão e reportou os 5 blocos (A–E) passando, sem bugs.** Registrado em nível de bloco em `macos/.specs/project/STATE.md` — não há detalhamento item-a-item (✅/❌ por linha) nesta sessão. Gate do `release-1.0` fechado.


- Preencher ✅/❌ + observação em cada item acima.
- Sintetizar resultados em `macos/.specs/project/STATE.md` e marcar os `T#` correspondentes (T38, T47, T28, T57, T61) como ☑ nos respectivos `tasks.md`.
- Qualquer bug achado ao vivo: corrigir, teste de regressão se fizer sentido, documentar em `STATE.md` (mesmo padrão de toda sessão anterior do projeto).
- Se tudo verde: Fase 1 de [`release-1.0/tasks.md`](../../../.specs/features/release-1.0/tasks.md) fecha → seguir Fases 2–5 (versão/build, docs já prontos, tags, publicação).
