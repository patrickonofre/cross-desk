# Context — file-transfer (decisões do usuário, 2026-07-04)

Áreas cinzas levantadas na especificação e resolvidas com o usuário:

## 1. Modelo de UX da primeira entrega

**Decisão: ⌘C/⌘V de arquivos primeiro + spike do drag em paralelo (staged).**

Alternativas consideradas:
- *Drag real direto* — rejeitada como primeira entrega: risco alto (Synergy bugado e removido do Deskflow; técnica de janela invisível + eventos sintéticos não provada), retrabalho provável.
- *Shelf/drop-zone* — rejeitada: zero risco técnico, porém menos natural que ⌘C/⌘V e adiciona UI própria.

Racional: a infraestrutura de transferência (canal confiável, chunking, integridade, progresso) é ~70% do trabalho e é comum a qualquer UX. ⌘C/⌘V entrega valor com API 100% pública; o drag real (E2) só recebe investimento se o spike S1 provar a técnica.

## 2. Destino quando o drop/paste não tem alvo claro

**Decisão: `~/Downloads/CrossDesk/`** (criada sob demanda, reveal no Finder ao concluir).

Alternativas: Desktop (polui a mesa — comportamento do Synergy antigo); pasta configurável (adiada — pode virar config depois sem quebrar nada).

## Delegado ao design (não são decisões de produto)

- Transporte do canal de arquivos: segunda conexão TCP+TLS-PSK vs. camada confiável sobre o DTLS/UDP existente (R8 — não degradar input — pesa aqui).
- Materialização do paste: transferência antecipada (eager, pasteboard com URL real) vs. sob demanda (promise) — confiabilidade do ⌘V no Finder decide.
- Threshold de UI para mostrar progresso.
