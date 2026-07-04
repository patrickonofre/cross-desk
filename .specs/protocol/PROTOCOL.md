# CrossDesk Protocol — v0.1 (DRAFT)

Contrato de rede entre as apps nativas (macOS, Windows, Linux). Toda implementação DEVE cumprir esta spec e passar nos golden test vectors (`.specs/protocol/vectors/`, criados junto com a implementação de referência — a app macOS).

> Status: DRAFT — congela em v1.0 quando a app macOS (implementação de referência) fechar o MVP. Até lá, mudanças são permitidas mas devem ser registradas no Changelog abaixo.

## 1. Transporte

- **UDP**, porta padrão **24800** (herança simbólica do Synergy; configurável).
- Criptografia obrigatória: **DTLS 1.2 com PSK** — cipher suite `TLS_PSK_WITH_AES_128_GCM_SHA256`. Sem modo plaintext. (Validado no spike T1: Network.framework/macOS suporta nativamente.)
- **PSK** = `HKDF-SHA256(normalize(código), salt="crossdesk-v1", info="dtls-psk")`, identidade PSK = `"crossdesk"`. `normalize` = remove tudo que não é alfanumérico + lowercase (o hífen de exibição do token e diferenças de caixa não alteram a chave).
- **Duas fontes de código, mesmo HKDF** (ciclo de vida do pareamento):
  1. **Token curto de pareamento** — gerado e exibido pelo servidor não-pareado (8 chars, alfabeto sem ambíguos `23456789ABCDEFGHJKMNPQRSTVWXYZ`, exibido `XXXX-XXXX`, ≈39 bits); usuário digita no cliente uma vez. Vale só para a janela de pareamento.
  2. **Segredo de longo prazo** — 32 hex chars (128 bits), gerado pelo servidor e entregue ao cliente via `PAIR_SET` **dentro do túnel DTLS** estabelecido com o token; ambos persistem e todos os handshakes seguintes usam ele (rotação: ver §3, PAIR_SET/PAIR_ACK).
- Nota de segurança: PSK sem (EC)DHE não tem forward secrecy; um segredo fraco permite brute-force offline do tráfego capturado. O token curto é brute-forceável offline por um sniffer que capture o(s) handshake(s) da janela de pareamento — janela de segundos, uma vez por par; o segredo rotacionado (128 bits) não é derivável do token. Brute-force online do token é impraticável (servidor aceita 1 conexão por vez; handshake com timeout serializa tentativas). Limitação aceita e documentada; eliminação definitiva: PAKE (SPAKE2) na Fase 4.
- Servidor escuta; cliente conecta. Papéis fixos por sessão.
- Datagramas de aplicação ≤ 1200 bytes (evita fragmentação IP).

## 2. Framing

Cada datagrama DTLS carrega **uma ou mais mensagens** concatenadas:

```
+--------+--------+----------------+
| type   | length | payload        |
| u8     | u16 LE | length bytes   |
+--------+--------+----------------+
```

- Byte order: **little-endian** em todos os campos multi-byte.
- `length` = tamanho do payload (não inclui o cabeçalho de 3 bytes).
- Mensagem com `type` desconhecido: ignorar e pular `length` bytes (forward-compat).

## 3. Mensagens

| type | Nome | Direção | Payload |
|------|------|---------|---------|
| 0x01 | HELLO | C→S | `proto_version u16` · `name_len u8` · `name utf8` |
| 0x02 | HELLO_ACK | S→C | `proto_version u16` (versão negociada = min das duas) |
| 0x03 | HEARTBEAT | ambas | vazio; enviar a cada 2 s; timeout 6 s |
| 0x04 | BYE | ambas | vazio; encerramento limpo |
| 0x05 | PAIR_SET | S→C | `code_len u8` · `code utf8` (segredo de longo prazo, 32 hex chars) — enviado após HELLO quando a sessão foi estabelecida com o token curto; **reenviar a cada 2 s até PAIR_ACK, sempre com o MESMO segredo** (idempotente sobre UDP). Cliente persiste ao receber; duplicata → re-persiste (mesmo valor) e re-ACKa |
| 0x06 | PAIR_ACK | C→S | vazio — cliente persistiu o segredo. Servidor persiste o segredo **somente ao receber o ACK** e passa a aceitar handshakes novos apenas com ele |
| 0x10 | ENTER | S→C | `x f32` · `y f32` (posição normalizada 0.0–1.0 no espaço de telas do cliente) · `edge u8` (borda do cliente por onde o cursor entra: 0=left, 1=right, 2=top, 3=bottom — também é a borda de retorno) |
| 0x11 | LEAVE | S→C | vazio — controle voltou ao servidor; cliente libera modificadores pressionados |
| 0x12 | LEAVE_REQUEST | C→S | `x f32` · `y f32` (posição normalizada de saída) — cursor do cliente cruzou a borda de retorno; servidor responde com LEAVE. Pode repetir até o LEAVE chegar (perda UDP) — servidor DEVE tratar como idempotente |
| 0x20 | MOUSE_MOVE | S→C | `dx f32` · `dy f32` (deltas relativos, px) |
| 0x21 | MOUSE_BUTTON | S→C | `button u8` (1=esq, 2=dir, 3=meio, 4+=extra) · `pressed u8` (0/1) |
| 0x22 | SCROLL | S→C | `dx f32` · `dy f32` (linhas; positivo = direita/baixo) — roda física discreta |
| 0x23 | SCROLL_CONTINUOUS | S→C | `dx f32` · `dy f32` (pixels; positivo = direita/baixo) · `phase u8` (0=none 1=began 2=changed 3=ended 4=cancelled) · `momentum u8` (0=none 1=began 2=changed 3=ended) — scroll de trackpad de alta fidelidade; fases repassadas da origem (momentum não é sintetizado) |
| 0x30 | KEY | S→C | `hid_usage u16` (USB HID Usage ID, página 0x07) · `pressed u8` (0/1) |
| 0x40 | CLIPBOARD | ambas | reservado (Fase 4) |

## 4. Keycodes

**USB HID Usage IDs, Usage Page 0x07 (Keyboard/Keypad)** — representação neutra no fio.

- macOS: tabela CGKeyCode ↔ HID usage.
- Windows: scancode (set 1) ↔ HID usage.
- Linux: evdev keycode ↔ HID usage.
- Cada app mantém sua tabela de mapeamento localmente; o fio só conhece HID.
- Modificadores trafegam como teclas normais (LeftShift=0xE1, LeftCtrl=0xE0 etc.) — estado é derivado, nunca enviado como flags.

## 5. Semântica

- **Cada máquina é dona da própria geometria de telas** — resolução e layout de monitores NUNCA trafegam. Posições no fio são sempre normalizadas 0.0–1.0.
- MOUSE_MOVE são **deltas relativos**; o cliente é dono da posição absoluta do seu cursor, contido na topologia real dos seus monitores (desliza em bordas, cruza para monitores adjacentes).
- Scroll tem dois canais: **SCROLL (0x22)** para roda física (linhas, passos discretos) e **SCROLL_CONTINUOUS (0x23)** para trackpad (pixels + fase de gesto + fase de momentum). O servidor classifica na captura (evento contínuo vs. discreto) e o cliente injeta com a unidade correspondente. Fases de momentum são geradas pela origem e apenas repassadas — o cliente não sintetiza inércia.
- ENTER carrega posição normalizada (sobre o bounding box da união das telas do cliente) + a borda de entrada, para o cursor "nascer" no ponto correspondente. A borda de entrada é também a borda de retorno.
- **A borda de retorno é detectada no CLIENTE** (dono da verdade sobre a posição do seu cursor): ao cruzar a borda externa de retorno, envia LEAVE_REQUEST com a posição normalizada de saída; o servidor reposiciona seu cursor físico e responde LEAVE. LEAVE_REQUEST pode se repetir a cada movimento adicional "para fora" enquanto o LEAVE não chega — retry natural sobre UDP; servidor idempotente (ignora quando já está em LOCAL).
- Após LEAVE, cliente DEVE soltar (key-up sintético) toda tecla que estiver logicamente pressionada — evita modificador preso.
- Eventos de input fluem S→C; LEAVE_REQUEST é a única mensagem de controle C→S (além de HELLO/HEARTBEAT/BYE).
- Sem ACK por evento (UDP é lossy por design; perda de MOUSE_MOVE é tolerável). KEY e MOUSE_BUTTON: v0.1 aceita perda; se na prática incomodar, v0.2 adiciona canal confiável só para eventos discretos (registrado como risco).

## 6. Pareamento (rotação token → segredo)

Regras que tornam a rotação segura sobre UDP (toda implementação DEVE cumprir):

- **Servidor persiste no ACK; cliente persiste no SET.** Nunca o contrário.
- Cliente DEVE guardar o token digitado até completar um handshake com o segredo; se o handshake com o segredo falhar por timeout e houver token conhecido, DEVE tentar o token no ciclo seguinte (cobre "servidor esqueceu o pareamento" e ACK perdido — o servidor então gera segredo novo e roda a rotação de novo).
- PAIR_SET fora da janela de pareamento (sessão estabelecida com o segredo) não deve ocorrer; se ocorrer, cliente trata igual (persiste + ACKa) — o servidor é a autoridade do segredo.
- Cliente antigo (não implementa 0x05/0x06) ignora PAIR_SET (§2) e nunca ACKa: servidor permanece em modo token — funcional, sem rotação.

Análise de falha completa (perda de SET/ACK, queda no meio): design da implementação de referência (`macos/.specs/features/discovery-pairing/design.md`).

## 7. Descoberta (Bonjour/mDNS)

- Serviço **`_crossdesk._udp`**, anunciado pelo servidor **enquanto estiver ativo** (anúncio some quando o servidor para). Porta real via registro SRV (a porta configurada pode diferir da padrão).
- Nome da instância = nome do dispositivo (ex.: "Mac do Patrick"). Colisão de nome: comportamento padrão mDNS (rename automático "Nome (2)") — aceito.
- TXT record: `proto=<proto_version>` (decimal). **Nada sensível no anúncio** (sem token, sem fingerprint, sem segredo). O TXT é conveniência de UI; NENHUMA decisão de segurança pode se basear nele — a autenticação é exclusivamente o handshake DTLS-PSK.
- Cliente navega o mesmo tipo de serviço e conecta no endpoint resolvido. Fallback manual (host+porta digitados) DEVE continuar existindo (redes com mDNS bloqueado).

## 8. Versionamento

- `proto_version` u16: v0.1 = `1`. Incrementa a cada mudança incompatível.
- HELLO/HELLO_ACK negociam o mínimo comum; sem versão comum → BYE.

## Changelog

- v0.1 (2026-07-03): draft inicial.
- v0.1 (2026-07-03): auth trocada de certs+TOFU para DTLS-PSK com código de pareamento gerado (resultado do spike T1 — evita geração de certificado, UX mais simples).
- v0.1 (2026-07-03): geometria independente por máquina — ENTER ganha `edge u8`; nova mensagem LEAVE_REQUEST (0x12, C→S); borda de retorno detectada no cliente (antes: cursor virtual simulado no servidor — causava drift quando as resoluções diferiam). Golden vectors regenerados.
- v0.1 (2026-07-03): nova mensagem SCROLL_CONTINUOUS (0x23, S→C) para scroll de trackpad de alta fidelidade (pixels + fases). `proto_version` inalterado (=1): mensagem de tipo novo é ignorável por decoders antigos (§2), então é adição compatível. Golden vectors acrescidos.
- v0.1 (2026-07-04): pareamento por token curto + rotação — §1 reescrito (token 8 chars → segredo 128-bit via túnel), novas mensagens PAIR_SET (0x05, S→C) e PAIR_ACK (0x06, C→S), novo §6 (regras da rotação) e §7 (descoberta Bonjour `_crossdesk._udp`). `proto_version` inalterado (=1): tipos novos ignoráveis; cliente antigo fica em modo token (compatível). Golden vectors `pair_set`/`pair_ack` acrescidos.
