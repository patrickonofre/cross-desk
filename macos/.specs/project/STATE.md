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

- **2026-07-03 — Geometria independente por máquina (T16)**: borda de retorno detectada no CLIENTE (`LEAVE_REQUEST` 0x12), `VirtualCursor` do servidor removido. Motivo: simulação server-side driftava com resoluções diferentes (cursor "se perdia" no UAT). Cliente agora contém o cursor em TODOS os seus monitores (`ScreenTopology`). Resolução continua fora do fio (R8 preservado).

## Pendências

- [x] Golden vectors → `.specs/protocol/vectors/v0_1.txt` (provados por teste).
- [ ] Spike T2 (CGEventPost fora da main thread + Esc em REMOTE) — valida na prática durante T15/UAT.
- [ ] Pairing code em JSON plano → migrar para Keychain pós-MVP.
- [x] ~~Assinatura ad-hoc: TCC re-pedindo após rebuild~~ — RESOLVIDO (beta.3): identidade self-signed "CrossDesk Dev" no keychain da máquina de build, make-app.sh auto-detecta (fallback ad-hoc). Cert Apple Developer real continua desejável p/ notarização (elimina o passo do xattr).
- [ ] Cursor do servidor fica visível parado na borda durante REMOTE (esconder cursor exige APIs privadas/hacks — avaliar pós-MVP).

## Lições (cont.)

- Simular a posição do cursor remoto no servidor (duas contabilidades da mesma verdade) drifta assim que as resoluções diferem — quem injeta o cursor é a única fonte de verdade da posição dele.

- `NWConnection` presa em `.preparing` (porta morta) nunca vira `.failed` sozinha — timeout de handshake é obrigatório em UDP/DTLS.
- Enfileirar `send()` público (queue.async) de dentro de um bloco já na queue = mensagem sai depois do teardown. Métodos internos *OnQueue diretos.
- **Confirmado na prática (beta.1→beta.2):** update de app ad-hoc quebra TCC nas duas máquinas — toggle aparece ligado em System Settings mas o preflight falha, e re-conceder NÃO regrava a entrada. Cura: `tccutil reset All dev.crossdesk.mac` + conceder de novo. Prevenção: identidade de assinatura estável.

## Lições

- (vazio)

## Preferences

- (herda da raiz)
