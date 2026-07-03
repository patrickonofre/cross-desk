# STATE — CrossDesk macOS

## Decisões

- **2026-07-03 — macOS 14+ como alvo mínimo** (habilita MenuBarExtra estável, SMAppService, APIs modernas de Network.framework). Assumido, não confirmado com usuário — fácil de baixar para 13 se preciso.
- **2026-07-03 — App única com dois papéis** (servidor OU cliente, toggle na UI), não duas apps.
- **2026-07-03 — Lógica em SPM packages locais** (CrossDeskKit), app Xcode só como casca — testes rodam via `swift test` sem GUI.

## Bloqueios

- Nenhum.

## Decisões (cont.)

- **2026-07-03 — DTLS-PSK confirmado (T1 ✅)**: Network.framework faz DTLS 1.2 + `TLS_PSK_WITH_AES_128_GCM_SHA256` nativamente. Auth por código de pareamento gerado (128 bits) → HKDF → PSK. Certificados/TOFU descartados. QUIC fallback não necessário.

- **2026-07-03 — App como executável SPM + make-app.sh** (SPEC_DEVIATION do design "casca Xcode"): bundle montado por script, assinatura ad-hoc. Registrado em tasks.md T14.

## Pendências

- [x] Golden vectors → `.specs/protocol/vectors/v0_1.txt` (provados por teste).
- [ ] Spike T2 (CGEventPost fora da main thread + Esc em REMOTE) — valida na prática durante T15/UAT.
- [ ] Pairing code em JSON plano → migrar para Keychain pós-MVP.
- [ ] Assinatura ad-hoc: TCC pode re-pedir permissão após rebuild — resolver com cert de developer quando houver conta.
- [ ] Cursor do servidor fica visível parado na borda durante REMOTE (esconder cursor exige APIs privadas/hacks — avaliar pós-MVP).

## Lições (cont.)

- `NWConnection` presa em `.preparing` (porta morta) nunca vira `.failed` sozinha — timeout de handshake é obrigatório em UDP/DTLS.
- Enfileirar `send()` público (queue.async) de dentro de um bloco já na queue = mensagem sai depois do teardown. Métodos internos *OnQueue diretos.

## Lições

- (vazio)

## Preferences

- (herda da raiz)
