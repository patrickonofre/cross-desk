# Context — discovery-pairing (decisões do usuário)

Capturadas em 2026-07-03 via perguntas diretas antes do design.

## 1. Formato do token

**Decisão: curto + rotação.** Token de pareamento de 8 chars (~40 bits) exibido no servidor; após o 1º handshake bem-sucedido, as apps trocam um segredo forte de 128 bits por dentro do túnel DTLS e passam a usá-lo. Risco residual aceito e documentado: sniffer na LAN durante a janela de pareamento pode quebrar o token curto offline (janela de segundos; PAKE na Fase 4 elimina). Alinhado ao roadmap raiz (Fase 4: "pareamento com código curto").

- Alternativa rejeitada: manter 128-bit digitado (32 hex chars) — seguro mas UX ruim; descoberta só eliminaria o IP.

## 2. Reconexão

**Decisão: automática.** Segredo fica salvo; cliente reconecta sozinho ao servidor pareado. Botão "Esquecer pareamento" nos dois lados para resetar.

- Alternativa rejeitada: exigir token a cada conexão.

## 3. Fallback manual

**Decisão: manter.** Campo IP/hostname continua existindo atrás de "Conectar por IP…" — redes corporativas às vezes bloqueiam mDNS.

- Alternativa rejeitada: só descoberta (sem saída se mDNS falhar).
