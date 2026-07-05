# Spec — file-transfer (compartilhamento de arquivos mac↔mac)

Transferir arquivos entre as máquinas pareadas. Entrega em duas etapas (decisão do usuário, [context.md](context.md)):

- **E1 — Clipboard de arquivos:** copiar arquivo(s) no Finder de uma máquina (⌘C) e colar na outra (⌘V), nos dois sentidos.
- **E2 — Drag real (condicional):** arrastar arquivo cruzando a borda e soltar na outra máquina. Só entra se o spike S1 provar a técnica; caso contrário, o drop degrada para a pasta de destino (R6). Escopo detalhado da E2 será especificado após o spike.

Contexto de viabilidade: Synergy implementou drag real e ficou "extremamente bugado" (só mac→win, drop sempre no Desktop); Deskflow removeu a feature. ShareMouse (pago) é o único que faz bem. Por isso o staged: E1 é 100% API pública e entrega o valor central (arquivo sai de uma máquina e chega na outra); E2 é aposta de UX com spike antes de qualquer investimento.

## Requisitos — E1

- **R1 — Copiar/colar nos dois sentidos.** Arquivos copiados no pasteboard de uma máquina ficam disponíveis para colar na outra, independente de qual é servidor ou cliente.
- **R2 — Colar natural.** ⌘V na máquina de destino materializa o(s) arquivo(s) como se fossem locais (colar numa pasta do Finder coloca os arquivos nela). Estratégia de materialização (transferência antecipada vs. sob demanda) é decisão de design.
- **R3 — Múltiplos arquivos e pastas.** Seleções múltiplas e diretórios (recursivo) são suportados. Symlinks não são seguidos (transferidos como link, nunca resolvendo fora da árvore copiada).
- **R4 — Progresso e cancelamento.** Transferência acima de um threshold de UI mostra progresso (por item e total) e permite cancelar. Sem limite duro de tamanho.
- **R5 — Integridade atômica.** Arquivo em transferência nunca aparece parcial no destino: escrita em arquivo temporário (`.part`) + rename atômico ao concluir; verificação de integridade por SHA-256. Falha/cancelamento no meio → temporário removido, erro visível, re-tentativa manual (transferência não é retomável na E1).
- **R6 — Pasta de destino fallback.** Quando o destino não é um paste com alvo claro (e no drop da E2 sem app alvo), os arquivos caem em `~/Downloads/CrossDesk/` (criada sob demanda), com reveal no Finder ao concluir.
- **R7 — Segurança.** Transferência exclusivamente dentro de canal criptografado autenticado pelo mesmo segredo do pareamento (sem modo plaintext, coerente com PROTOCOL.md §1). Receptor sanitiza nomes recebidos (rejeita `..`, separadores e nomes reservados — sem path traversal). Colisão de nome no destino: sufixo incremental (`arquivo (2).ext`), nunca sobrescrita silenciosa.
- **R8 — Input não degrada.** Transferência grande em andamento não pode degradar perceptivelmente a latência de input (canal/priorização separados do fluxo de eventos — decisão de design).
- **R9 — Protocolo neutro e compatível.** Mensagens novas especificadas no PROTOCOL.md com golden vectors; implementação antiga ignora tipos desconhecidos (§2) e a feature degrada limpo (sem transferência, sem crash). `proto_version` inalterado se a adição for ignorável.

## Requisitos — E2 (pós-spike)

- **R10 — Spike S1 decide o drag.** Técnica candidata: janela invisível sob o cursor no destino + `beginDraggingSession` com `NSFilePromiseProvider`, movida por eventos injetados. Critérios de aprovação do spike: (a) sessão de drag inicia a partir de evento sintético; (b) drop aceito por Finder e por um app comum (ex.: Mail); (c) promise resolve após transferência concluir sem travar o app alvo. Reprovou → E2 vira "soltar → arquivo cai em R6" ou é descartada (decisão na hora, com evidência).

## Não-objetivos

- Clipboard de texto/imagem (feature própria, Fase 4 — mas o canal de transferência criado aqui é reutilizável por ela).
- Transferência retomável, compressão, delta.
- Windows/Linux (herdam o contrato do PROTOCOL.md nas Fases 2/3).

## Aceitação (E1)

1. Copiar 1 arquivo pequeno no servidor → ⌘V numa pasta do Finder do cliente → arquivo íntegro na pasta (e vice-versa, cliente→servidor).
2. Arquivo grande (≥1 GB): progresso visível, cancelável; cancelou → sem lixo no destino.
3. Pasta com subpastas e múltiplos arquivos: árvore reproduzida fielmente no destino.
4. Rede cai no meio da transferência: erro visível, nenhum arquivo parcial/corrompido no destino, input volta a funcionar sozinho quando a conexão volta.
5. Nome malicioso (`../evil`, separadores): rejeitado/sanitizado, nunca escreve fora do destino.
6. Colisão de nome: gera `nome (2).ext`, não sobrescreve.
7. Durante transferência de arquivo grande, mover mouse/digitar na máquina remota permanece fluido (sem stutter perceptível).
8. Build antigo (sem a feature) conectado a build novo: sessão funciona normal, mensagens novas ignoradas.
