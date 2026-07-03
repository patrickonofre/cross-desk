# CrossDesk Protocol — v0.1 (DRAFT)

Contrato de rede entre as apps nativas (macOS, Windows, Linux). Toda implementação DEVE cumprir esta spec e passar nos golden test vectors (`.specs/protocol/vectors/`, criados junto com a implementação de referência — a app macOS).

> Status: DRAFT — congela em v1.0 quando a app macOS (implementação de referência) fechar o MVP. Até lá, mudanças são permitidas mas devem ser registradas no Changelog abaixo.

## 1. Transporte

- **UDP**, porta padrão **24800** (herança simbólica do Synergy; configurável).
- Criptografia obrigatória: **DTLS 1.2 com PSK** — cipher suite `TLS_PSK_WITH_AES_128_GCM_SHA256`. Sem modo plaintext. (Validado no spike T1: Network.framework/macOS suporta nativamente.)
- **PSK** = `HKDF-SHA256(código_de_pareamento, salt="crossdesk-v1", info="dtls-psk")`, identidade PSK = `"crossdesk"`. O **servidor gera** o código de pareamento (aleatório, ≥128 bits de entropia, exibido em formato copiável); usuário insere no cliente uma vez.
- Nota de segurança: PSK sem (EC)DHE não tem forward secrecy e um código fraco permite brute-force offline do tráfego capturado — por isso o código é sempre gerado (nunca inventado pelo usuário). Upgrade futuro: PAKE (SPAKE2) na Fase 4.
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
| 0x10 | ENTER | S→C | `x f32` · `y f32` (posição normalizada 0.0–1.0 na tela do cliente) — cursor entrou na tela do cliente |
| 0x11 | LEAVE | S→C | vazio — controle voltou ao servidor; cliente libera modificadores pressionados |
| 0x20 | MOUSE_MOVE | S→C | `dx f32` · `dy f32` (deltas relativos, px) |
| 0x21 | MOUSE_BUTTON | S→C | `button u8` (1=esq, 2=dir, 3=meio, 4+=extra) · `pressed u8` (0/1) |
| 0x22 | SCROLL | S→C | `dx f32` · `dy f32` (linhas; positivo = direita/baixo) |
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

- MOUSE_MOVE são **deltas relativos**; o cliente é dono da posição absoluta do seu cursor (clamp nas bordas da própria tela).
- ENTER carrega posição normalizada para o cursor "nascer" no ponto correspondente da borda.
- Após LEAVE, cliente DEVE soltar (key-up sintético) toda tecla que estiver logicamente pressionada — evita modificador preso.
- Eventos de input só fluem S→C. Bordas do cliente que devolvem o cursor são detectadas **no servidor** (via geometria do layout), não pelo cliente.
- Sem ACK por evento (UDP é lossy por design; perda de MOUSE_MOVE é tolerável). KEY e MOUSE_BUTTON: v0.1 aceita perda; se na prática incomodar, v0.2 adiciona canal confiável só para eventos discretos (registrado como risco).

## 6. Versionamento

- `proto_version` u16: v0.1 = `1`. Incrementa a cada mudança incompatível.
- HELLO/HELLO_ACK negociam o mínimo comum; sem versão comum → BYE.

## Changelog

- v0.1 (2026-07-03): draft inicial.
- v0.1 (2026-07-03): auth trocada de certs+TOFU para DTLS-PSK com código de pareamento gerado (resultado do spike T1 — evita geração de certificado, UX mais simples).
