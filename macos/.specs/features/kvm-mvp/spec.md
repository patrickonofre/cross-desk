# Spec — kvm-mvp (app macOS, MVP mac↔mac)

**Escopo:** Complex (domínio novo: event taps, DTLS, protocolo próprio). Pipeline completo: spec → design → tasks → execute.

## Objetivo

Duas máquinas macOS na mesma LAN: uma servidor (dona de teclado/mouse), outra cliente. Cursor cruza a borda configurada e passa a controlar o cliente; teclado segue o cursor; cursor volta pela borda oposta. Tráfego 100% criptografado.

## Requisitos

### Servidor

- **R1** — Capturar mouse e teclado globais via CGEventTap quando o controle está no cliente; eventos NÃO chegam às apps locais do servidor (tap com supressão, `kCGEventTapOptionDefault`).
- **R2** — Detectar cruzamento de borda: lado configurável (esquerda/direita/cima/baixo) mapeado para o cliente. Ao cruzar: enviar `ENTER` com posição normalizada, ocultar transição (cursor local para de mover).
- **R3** — Devolver controle quando o cliente reporta `LEAVE_REQUEST` (borda de retorno detectada **no cliente**, dono da própria geometria — protocolo §5): reposicionar o cursor físico na altura correspondente, enviar `LEAVE`, restaurar cursor local. Idempotente a LEAVE_REQUEST duplicado.
- **R4** — Atalho de emergência global (padrão: pressionar `Esc` 3× em 1 s) devolve o controle ao servidor incondicionalmente — rede caída não pode sequestrar o input.
- **R5** — Encodar eventos conforme [PROTOCOL.md](../../../../.specs/protocol/PROTOCOL.md) v0.1 (deltas relativos, HID usages).

### Cliente

- **R6** — Receber eventos e injetar via CGEventPost: movimento relativo contido na **topologia real de todos os monitores locais** (desliza em bordas, cruza para monitor adjacente), cliques, scroll, teclas (HID→CGKeyCode).
- **R7** — Em `LEAVE` ou desconexão: key-up sintético de toda tecla logicamente pressionada (nunca deixar modificador preso).
- **R8** — Identificar-se no HELLO só pelo nome da máquina; **geometria/resolução nunca trafegam** — cada máquina é dona da própria topologia (posições no fio são normalizadas). Cliente detecta a própria borda de retorno e envia `LEAVE_REQUEST`.

### Transporte e segurança

- **R9** — DTLS-PSK sobre UDP porta 24800 (configurável), conforme protocolo §1: servidor gera código de pareamento (≥128 bits, copiável), cliente o insere uma vez; PSK derivada via HKDF. Sem modo plaintext.
- **R10** — Reconexão automática do cliente com backoff (1 s → 30 s máx); HEARTBEAT/timeout conforme protocolo §3.

### UI e config

- **R11** — MenuBarExtra: papel (servidor/cliente), status da conexão (cor/ícone), campo host:porta + código de pareamento no cliente, lado da borda + exibição do código gerado no servidor, iniciar/parar.
- **R12** — Onboarding TCC: detectar Input Monitoring (servidor) e Accessibility (cliente) via preflight; botão que abre o painel certo de System Settings; estado refletido na UI.
- **R13** — Config persistida em JSON (`~/Library/Application Support/CrossDesk/config.json`); recarregada no launch.

### Qualidade

- **R14** — Latência captura→injeção p95 ≤ 15 ms na LAN cabeada/Wi-Fi 5 GHz (medida com clock sincronizado ou RTT/2).
- **R15** — Conformidade de protocolo: encoder/decoder validados por golden vectors versionados em `.specs/protocol/vectors/`.

## Fora de escopo (MVP)

- Clipboard, discovery mDNS, pareamento por código, multi-cliente (>1), layout drag-and-drop, autostart, notarização/distribuição, robustez a sleep/wake.

## Aceitação (UAT)

1. Dois macs, mesma LAN, **resoluções diferentes**. Servidor configura borda direita → cliente. Cursor cruza, aparece no cliente na altura correspondente; ida e volta repetidas não acumulam desvio (sem drift).
2. Digitar no cliente (incluindo ⌘C/⌘V, acentos via modificadores) funciona; apps locais do servidor não recebem os eventos.
3. Cursor volta pela borda esquerda do cliente. Modificadores não ficam presos.
4. Cabo de rede puxado com controle no cliente → atalho de emergência devolve o input em ≤ 1 s.
5. Tráfego inspecionado (Wireshark): nenhum byte de payload legível.
