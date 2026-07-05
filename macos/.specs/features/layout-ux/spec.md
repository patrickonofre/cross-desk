# layout-ux — Spec

**Status**: Approved (2026-07-05)
**Fase**: 1 (app macOS) — camada de UX sobre kvm-mvp/discovery-pairing/file-transfer
**Criada**: 2026-07-05

---

## Problema

A UI atual é um formulário: picker de borda (Direita/Esquerda/Cima/Baixo), listas, texto de status. O usuário não *vê* a mesa dele — quais monitores tem, onde o outro Mac está, onde o cursor está agora. Pesquisa de mercado (ver design.md §Pesquisa) mostra que todo par maduro convergiu para representação espacial: macOS Ajustes → Monitores (arrastar retângulos), Universal Control, Synergy 3 (canvas livre), Mouse Without Borders (caixas arrastáveis). O picker de enum é o piso (lan-mouse faz igual), não o teto.

## Objetivo

O usuário entende e configura o CrossDesk **olhando para uma miniatura da própria mesa**: monitores locais reais, o outro Mac posicionado do lado certo, e estado vivo (quem tem o foco, travessia, transferência) — sem novo conceito, reusando o modelo mental de Ajustes → Monitores que todo usuário de Mac já tem.

## Requisitos

### R35 — Mini-mapa vivo no painel do menubar

O painel ganha um mini-mapa no topo: telas locais (forma agregada) + tile do outro Mac posicionado conforme a borda configurada. Mostra em tempo real: ponto de foco (em qual Mac o cursor está), estado da sessão por cor, transferência em andamento. Clicar abre a janela de telas (R36). Substitui nada — o status textual continua abaixo dele.

**Aceitação**: com sessão conectada, mover o cursor para o Mac remoto move o ponto de foco no mini-mapa em <1 s; parar a sessão esvazia o mapa.

### R36 — Janela "Telas" (editor de layout)

Nova janela (SwiftUI `Window`, aberta pelo painel) com canvas:

- **Monitores locais reais**: `Displays.activeBounds()` em escala, laptop identificado por `CGDisplayIsBuiltin` (silhueta com base), monitores externos como retângulos com nome (`NSScreen.localizedName`).
- **Outro Mac como tile abstrato** (proporção fixa 16:10, nome do peer): a geometria real dele NUNCA trafega (protocolo §5) — o tile carrega a legenda "telas organizadas lá", e o mesmo editor aberto no outro Mac mostra o espelho.
- Estado vazio (não pareado): tile tracejado + CTA de pareamento.

**Aceitação**: com 2 monitores físicos, o canvas reflete a disposição real (posição relativa e proporção aproximada); desconectar um monitor atualiza o canvas sem reabrir a janela.

### R37 — Arrastar o tile define a borda

No papel **servidor**, arrastar o tile do peer e soltar em um dos 4 lados da união das telas locais grava `config.edgeSide` (snap com pré-visualização da borda ativa durante o drag). O picker de enum atual **permanece** no painel como controle equivalente (acessibilidade R40 e ajuste rápido). No papel **cliente**, o tile do servidor aparece na borda de retorno detectada (borda de entrada do último ENTER) — somente leitura, com explicação ("definido pelo servidor").

**Aceitação**: arrastar o tile da direita para cima → `edgeSide == .top` persistido; reiniciar a sessão usa a nova borda; picker e canvas nunca divergem.

### R38 — Estado vivo nos dois níveis (cenários)

Mini-mapa (R35) e janela (R36) refletem a máquina de estados existente (`SessionState` + `TransferUIState`), sem estado novo:

| Estado | Visual |
|---|---|
| `stopped` | tile ausente/apagado, borda apagada |
| `waitingPeer` (pareando) | tile tracejado, token em destaque (R28 preservado) |
| `waitingPeer` (pareado) | tile sólido esmaecido, borda apagada |
| `connected` | ponto de foco no Mac local, borda ativa acesa |
| `controllingRemote` | ponto de foco no tile remoto, telas locais esmaecidas, contorno no tile |
| transferência ativa | seta/chip na direção do fluxo com progresso |
| `error` | banner com a mensagem, mapa esmaecido |

**Aceitação**: cada transição de `sessionState` muda o visual em <1 s, sem interação.

### R39 — Microcopy de travessia (onboarding leve)

Após o primeiro pareamento bem-sucedido, o painel/janela mostram uma dica única e direcional: "Empurre o cursor pela borda **direita**" (lado dinâmico conforme `edgeSide`). Some após a primeira travessia (persistido em config). Modelo Universal Control: a primeira travessia é o onboarding — nenhum wizard.

**Aceitação**: dica aparece só entre parear e a primeira travessia; nunca reaparece depois (nem após restart).

### R40 — Acessibilidade

Canvas é *progressive enhancement*: toda ação tem equivalente acessível — picker de borda (mantido, R37), status textual (mantido). Tile e monitores com labels de VoiceOver ("MacBook de Ana, à direita das suas telas"). Foco/estado não comunicados só por cor (texto sempre presente).

**Aceitação**: VoiceOver lê estado e borda configurada sem tocar no canvas; mudar a borda é possível 100% via teclado.

### R41 — Ícone do menubar reflete o foco

Variação do ícone quando `controllingRemote` (ex.: preenchido/badge) — sinal de canto de olho de "meu teclado está indo para o outro Mac", visível mesmo com painel fechado.

**Aceitação**: ícone muda em REMOTE e volta em LOCAL/parado.

### R42 — Zero mudança de protocolo

Nada de novo no fio: geometria do peer não trafega (§5 mantido), o tile é abstrato. Extensão futura (troca opcional de silhueta/proporção das telas para um canvas bilateral em escala) fica registrada como ideia adiada — exigiria mensagem nova e decisão explícita.

**Aceitação**: diff da feature não toca `Protocol/` nem PROTOCOL.md (exceto nota de ideia adiada fora do fio).

## Não-objetivos

- Multi-cliente (>1 peer) no canvas — v1 é 1:1; o layout foi desenhado para escalar depois (tiles múltiplos), mas não agora.
- Redimensionar/sobrepor telas estilo Synergy 3 — sem necessidade no modelo §5 (cada máquina contém o próprio cursor).
- Offset ao longo da borda (alinhar o tile fora do centro) — candidato natural de v2; hoje a borda inteira é ativa.
- Geometria real do peer no fio (ver R42).
- Tema/branding novo — segue SwiftUI padrão do sistema.

## Dependências

- kvm-mvp (sessões, `SessionState`), discovery-pairing (token/descoberta), file-transfer (`TransferUIState`) — todas code-complete; UATs T28/T38/T47 pendentes são independentes desta feature, mas idealmente rodam antes (base estável).
