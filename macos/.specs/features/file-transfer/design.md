# Design — file-transfer (E1: clipboard de arquivos)

Referências: [spec.md](spec.md) (R1–R10), [context.md](context.md) (decisões do usuário), PROTOCOL.md §1–§3.

## Decisões de design

### D1 — Transporte: segunda conexão TCP + TLS-PSK, mesma porta em TCP

- Canal de arquivos = **TCP na mesma porta numérica** do UDP (24800 default; SRV do Bonjour já publica a porta). Listener TCP ativo apenas enquanto o servidor está ativo.
- **TLS 1.2 PSK** (`TLS_PSK_WITH_AES_128_GCM_SHA256`), espelho do DTLS existente. PSK derivado do MESMO segredo pareado, com **domain separation**: `HKDF(..., info="tls-psk-file")` (input usa `info="dtls-psk"`) — chaves independentes por canal, sem reuso cross-protocol.
- **TCP sempre iniciado pelo cliente** (coerente com §1 "servidor escuta; cliente conecta" — NAT/firewall). Quando o servidor precisa *receber* arquivos, ele pede via mensagem de controle no canal DTLS e o cliente abre o TCP e faz push.
- Conexão TCP é **por transferência** (abre sob demanda, fecha no fim) — zero custo quando não usada.
- Por que não confiável-sobre-DTLS: reimplementar ARQ+congestion control sobre datagramas ≤1200 B para GBs = reinventar TCP com risco de afogar o canal de input (R8). TCP em socket separado dá confiabilidade, backpressure e separação de filas de graça.
- ~~**Incerteza I1 (spike T40)**~~ — **MORTA (2026-07-05, spike passou)**: `NWListener`/`NWConnection` TCP com TLS 1.2 PSK (`TLS_PSK_WITH_AES_128_GCM_SHA256`, pin min/max TLSv12) faz handshake e sustenta stream de 1 MiB em loopback (`macos/spikes/tls-file-spike/`). Mesma API do DTLS (T1); plano B descartado.

### D2 — Fluxo eager com teto; announce barato sempre

1. **Watcher local**: poll de `NSPasteboard.general.changeCount` (0,5 s, só com sessão ativa). Pasteboard com file URLs → envia **CLIP_FILES** (metadata: id, nº de itens, bytes totais) ao par via DTLS. Barato, sempre.
2. **Materialização (lado destino)**:
   - `total ≤ teto` (default **200 MB**): transfere já (eager) para staging; ao concluir, escreve os URLs reais no pasteboard de destino → ⌘V nativo em qualquer app (R2).
   - `total > teto`: não transfere automático; painel mostra "N arquivos (X GB) — Receber agora" → destino `~/Downloads/CrossDesk/` (R6).
   - Teto configurável depois; v1 constante.
3. **Anti-loop obrigatório**: pasteboard escrito por nós carrega type privado `dev.crossdesk.transfer-id`; watcher ignora own-writes (senão announce ecoa infinito entre as máquinas).
4. **Incerteza I2 (spike T44):** `NSFilePromiseProvider` colado via ⌘V no Finder (lazy real, mataria o teto). Se provar → grandes viram promise; se não → teto+botão fica (fallback garantido, já entregue).
5. Race aceito na v1: ⌘V antes da transferência concluir cola conteúdo antigo (pasteboard destino só muda no fim — nunca arquivo parcial, R5). Progresso visível no painel cobre a percepção.

### D3 — Staging e materialização (R5/R6/R7)

- Staging: `~/Library/Caches/CrossDesk/incoming/<transfer_id>/` — chunks em `<nome>.part`, `rename()` atômico ao validar SHA-256 por item.
- Sanitização no receptor: caminho relativo recebido é normalizado; rejeita componente `..`, caminho absoluto, `~`, bytes NUL; symlink transferido como link, target gravado verbatim mas NUNCA resolvido/seguido na escrita.
- Colisão: sufixo ` (2)`, ` (3)`… antes da extensão. Nunca sobrescreve.
- Paste eager: URLs do staging no pasteboard (Finder copia dali; caches limpos por idade na inicialização). "Receber agora": move staging → `~/Downloads/CrossDesk/` + reveal no Finder.

### D4 — Protocolo (delta no PROTOCOL.md, com golden vectors)

Canal DTLS (controle, framing §2 existente — tipos ignoráveis por builds antigos, R9; `proto_version` inalterado):

| type | Nome | Direção | Payload |
|------|------|---------|---------|
| 0x50 | CLIP_FILES | ambas | `transfer_id u32` · `item_count u32` · `total_bytes u64` |
| 0x51 | FILE_PULL | S→C | `transfer_id u32` — servidor quer os arquivos anunciados pelo cliente; cliente abre TCP e faz push |

Canal TCP (framing próprio: `type u8 · length u32 LE · payload` — length u32 porque chunks excedem u16):

| type | Nome | Payload |
|------|------|---------|
| 0x01 | FILE_HELLO | `proto u16` · `transfer_id u32` · `mode u8` (0=push: quem conectou envia; 1=request: quem conectou pede) |
| 0x02 | ITEM_META | `kind u8` (0=arquivo 1=dir 2=symlink) · `size u64` · `path_len u16` · `path utf8` (relativo, `/` como separador) · se symlink: `target_len u16` · `target utf8` |
| 0x03 | DATA | bytes do item corrente (chunk ≤ 64 KiB) |
| 0x04 | ITEM_DONE | `sha256 (32 B)` (dir/symlink: omitido — payload vazio) |
| 0x05 | TRANSFER_DONE | vazio |
| 0x06 | CANCEL | `origin u8` (0=emissor 1=receptor) |
| 0x07 | ERROR | `code u8` · `msg_len u16` · `msg utf8` |

### D5 — R8 (input não degrada)

Sockets distintos (UDP input / TCP arquivos) → filas independentes no kernel. Adicional: chunks de 64 KiB com envio serializado por ACK implícito do TCP (backpressure natural do `send` do Network.framework); sem QoS custom na v1. Aceitação 7 (fluidez durante 1 GB) é o gate real no UAT; se falhar, mitigação: `NWParameters.serviceClass = .background` no canal de arquivos.

## Componentes

| Componente | Target | Papel |
|---|---|---|
| `FileChannelMessage` | Protocol | encode/decode do framing TCP (tabela D4) + vectors |
| `Message` (+0x50/0x51) | Protocol | mensagens de controle novas no framing DTLS |
| `FileChannelListener` / `FileChannelConnection` | Transport | listener TCP no servidor, connect no cliente, TLS-PSK (`info="tls-psk-file"`), lifecycle por transferência |
| `PasteboardWatcher` | FileTransfer (novo target) | poll changeCount, detecção de file URLs, anti-loop own-write |
| `FileSender` | FileTransfer | walk da seleção (recursivo, symlink não seguido), ITEM_META/DATA/ITEM_DONE, SHA-256 incremental |
| `FileReceiver` | FileTransfer | staging `.part`, sanitização, hash check, rename atômico, colisão, materialização (pasteboard/Downloads) |
| `TransferCoordinator` | FileTransfer | máquina de estados por transfer_id (announce→materialize→done/cancel), teto eager, integra Server/Client sessions |
| UI painel | app | linha de progresso + cancelar + "Receber agora" |

## Incertezas

1. ~~**I1** TLS-PSK/TCP no Network.framework~~ — morta (T40 ✅, ver D1).
2. **I2** promise-paste no Finder — spike T44, opcional (teto+botão é fallback entregue).
3. **I3** drag real (E2) — spike T48 (critérios no spec R10); independente da E1, pode rodar em paralelo após T41.

## Riscos

- Poll do pasteboard lendo dados grandes: mitigado — watcher lê apenas `types`/`changeCount`, nunca conteúdo.
- Loop de announce entre máquinas: mitigado por anti-loop D2.3 (teste unitário obrigatório).
- Cache staging crescendo: limpeza por idade (>24 h) no launch.
