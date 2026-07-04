# Spec — input-polish (cursor invisível/travado na máquina sem foco + fidelidade de mouse/teclado)

**Escopo:** Large (multi-componente: servidor, cliente, protocolo, integração com sistema). Pipeline: spec → design → tasks → execute.

**Contexto:** o kvm-mvp entregou a trava básica (R16 — `CGAssociateMouseAndMouseCursorPosition`), mas a seta ainda se move na máquina sem foco em cenários de standby/wake: a dissociação é estado global do WindowServer, aplicado uma única vez, e não sobrevive a transições de sistema (sleep/wake, screensaver, troca de sessão). "Robustez a sleep/wake" era fora-de-escopo declarado do kvm-mvp — esta feature assume esse débito. Aproveita para elevar a fidelidade geral de mouse/teclado (scroll de trackpad, autorepeat, convivência com input local) e instrumentar o caminho de input.

## Objetivo

Na máquina sem foco, a seta fica **invisível** (melhor esforço) e **imóvel** (garantido, auto-curável). Scroll de trackpad chega ao cliente com a mesma suavidade do local. Nenhuma transição de sistema (standby, wake, screensaver, mudança de monitores) degrada o estado de trava/ocultação.

## Requisitos

### Grupo A — Cursor na máquina sem foco

- **R17 — Seta invisível na máquina sem foco (melhor esforço).** Em REMOTE no servidor e em conectado-sem-foco no cliente, a seta é ocultada globalmente via `CGSSetConnectionProperty("SetsCursorInBackground")` + `CGDisplayHideCursor` (API privada — mesma técnica de Deskflow/Barrier; símbolos resolvidos dinamicamente, nunca linkados). Se a técnica falhar (macOS futuro, spike negativo), degrada para seta visível porém estacionada (R18) sem nenhum outro efeito colateral. Limitação documentada: o WindowServer devolve o cursor quando o Dock é o alvo ativo — aceito. Config `concealCursor` (default `true`).
- **R18 — Trava resiliente e auto-curável (endurece R16).** A dissociação deixa de ser a única defesa:
  - **Cliente (sem tap):** seta estacionada no ponto de retorno + watchdog leve (poll de `NSEvent.mouseLocation`/`CGEvent(source:nil).location` a ≤250 ms — zero permissão nova). Drift além de ε px → re-warp ao ponto de estacionamento + re-dissociação. Watchdog ativo apenas enquanto travado.
  - **Servidor (tem tap):** em REMOTE, cada `mouseMoved` capturado re-warpa a seta ao ponto de estacionamento (padrão Deskflow/lan-mouse — custo zero, o evento já chega ao tap).
  - Destravar continua incondicional em ENTER/desconexão/stop/exit (semântica R16 preservada).
- **R19 — Reassert em transições de sistema.** Acordar de sleep, screensaver encerrado, sessão reativada e reconfiguração de displays reaplicam o estado-alvo: cliente re-trava/re-oculta (se aplicável), servidor re-suprime + re-dissocia + re-habilita o tap, topologia e ponto de estacionamento recalculados. Fontes: `NSWorkspace.didWakeNotification`, `screensDidWakeNotification`, `sessionDidBecomeActiveNotification`, `CGDisplayRegisterReconfigurationCallback`. Nenhuma transição pode exigir reiniciar a app para restaurar o comportamento correto.

### Grupo B — Fidelidade de input

- **R20 — Scroll contínuo de alta fidelidade.** Scroll de trackpad (contínuo) trafega em nova mensagem `SCROLL_CONTINUOUS` (0x23): pixel deltas + fase (began/changed/ended) + fase de momentum. Injeção com `units: .pixel` + campos `scrollPhase`/`momentumPhase`/`isContinuous`. Roda física discreta permanece em `SCROLL` (0x22, linhas). Apps no cliente devem exibir scroll suave e (melhor esforço) rubber-band/momentum.
- **R21 — Injeção sem briga com input local.** O `CGEventSource` do injetor zera `localEventsSuppressionInterval` (e ajusta o filtro de supressão se necessário): tocar o trackpad do cliente durante REMOTE não pode congelar nem atrasar a injeção (default do sistema: 250 ms de supressão após cada evento injetado).
- **R22 — Autorepeat preservado.** KeyDown repetido capturado no servidor injeta com `kCGKeyboardEventAutorepeat` marcado — apps do cliente veem semântica de repeat correta (ex.: navegação segurando seta).

### Grupo C — Eficiência e observabilidade

- **R23 — Envio de MOUSE_MOVE sem backlog.** Sob trackpads de 90–120 Hz, a fila de envio não cresce: moves consecutivos ainda não enviados são fundidos (soma de deltas) no drain da fila — coalescing oportunista, sem timer, latência adicional zero quando a fila está vazia. Implementação condicionada à medição (R24) confirmar backlog; caso contrário registra-se a medição e o mecanismo fica dormente.
- **R24 — Métricas de input.** Contadores por sessão em log estruturado (`Logger` existente): eventos capturados/injetados por tipo, datagramas enviados/recebidos, merges de R23, warps de watchdog (R18), reasserts (R19). Base para o UAT desta feature e para fechar o p95 de latência (R14 do kvm-mvp, pendente do T15).

## Fora de escopo

- Esconder a seta quando o Dock é o alvo ativo do cursor (limitação do WindowServer — sem workaround sancionado).
- Overlay window para ocultação (alternativa DTS) — só entra se o spike da API privada falhar E estacionar visível for julgado insuficiente no UAT.
- Aceleração de ponteiro configurável no cliente (registrar sensação no UAT; feature própria se incomodar).
- Canal confiável para eventos discretos (risco já registrado no protocolo §5 — segue adiado).

## Aceitação (UAT)

1. **Standby/wake:** com controle no cliente, servidor entra em sleep de display e acorda → seta do servidor continua invisível/estacionada; input continua fluindo. Mesmo teste com o cliente dormindo (sem foco): ao acordar, seta do cliente permanece travada. Mexer o mouse físico da máquina sem foco por 30 s não produz movimento visível além de ε.
2. **Screensaver/sessão:** screensaver ativado e encerrado em ambas as máquinas → estado de trava/ocultação intacto sem reiniciar app.
3. **Invisibilidade:** com `concealCursor` ativo e spike positivo, a seta da máquina sem foco não é visível em uso normal (exceção Dock documentada).
4. **Scroll:** rolar página longa no cliente via trackpad do servidor → suave (pixel), com momentum ao soltar; roda física continua em passos de linha.
5. **Convivência local:** durante REMOTE, encostar no trackpad do cliente não congela a injeção por mais de um frame perceptível.
6. **Autorepeat:** segurar Backspace/seta no servidor apaga/navega continuamente no cliente com cadência do sistema.
7. **Métricas:** log estruturado exibe contadores ao fim da sessão; mover o mouse continuamente por 60 s não acumula backlog (fila estável, R23).
8. **Regressão:** aceitações 1–4 do kvm-mvp continuam passando (travessia, digitação, retorno, escape de emergência).

## Decisões pendentes de confirmação com o usuário

1. **API privada aceita?** Recomendação: sim — app já é indistribuível via App Store (tap com supressão exige não-sandbox); Deskflow/Barrier usam a mesma técnica há uma década; fallback garante degradação limpa. Confirmar antes do T20.
2. **Park point do cliente**: mantém borda de retorno (continuidade espacial, comportamento atual do R16). Alternativa canto-da-tela só se hide falhar E UAT reprovar a seta parada na borda.
