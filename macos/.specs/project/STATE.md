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

- **2026-07-03 — Ocultação de cursor via API privada aprovada (input-polish R17)**: `SetsCursorInBackground` (`CGSSetConnectionProperty` via `dlsym`) + `CGDisplayHideCursor` — mesma técnica de Deskflow/Barrier. Provado no spike T19 (macOS 26: símbolos resolvem, CGError=0). Fallback: seta parada-visível (warp-offscreen NÃO serve — clampa). Símbolos SEMPRE via `dlsym`, nunca linkados. App já é não-sandbox (tap com supressão), então API privada não muda o status de distribuição.
- **2026-07-03 — Trava de cursor não confia só na dissociação (input-polish R18/R19)**: `CGAssociateMouseAndMouseCursorPosition(0)` é estado global volátil (cai em sleep/wake). Defesa em camadas: servidor re-warpa a cada move capturado; cliente tem watchdog (`CursorSentinel`, poll 250 ms, sem TCC novo); ambos re-aplicam em wake/screensaver/display via `SystemStateObserver`. Padrão confirmado nos dois pares maduros (Deskflow/lan-mouse re-warpam continuamente).

## Decisões (cont. 2)

- **2026-07-04 — discovery-pairing especificada** (viabilidade confirmada): descoberta Bonjour nativa (`NWListener.Service` + `NWBrowser`, `_crossdesk._udp`, zero deps) + pareamento por token curto (8 chars, ~40 bits) com rotação para segredo 128-bit via PAIR_SET/PAIR_ACK (0x05/0x06) dentro do túnel DTLS. Decisões do usuário: token curto+rotação, reconexão automática, fallback manual por IP mantido. Risco aceito: brute-force offline do token na janela de pareamento (documentar no PROTOCOL.md; PAKE elimina na Fase 4). Docs: `.specs/features/discovery-pairing/` (spec/context/design/tasks T29–T38).

## Pendências

- [ ] **UAT consolidado marcado p/ 2026-07-06** — roteiro pronto em [project/UAT-2026-07-06.md](UAT-2026-07-06.md): bloco A = T38 (discovery-pairing), B = T47 (file-transfer), C = T28 (input-polish + p95 + decisões coalescing/reassert-park). Setup: build novo, `xattr -cr` na 2ª máquina, config.json limpo p/ testar pareamento do zero.
- [ ] **file-transfer E1 — CODE-COMPLETE (T39–T46 ✅), falta UAT T47** (2026-07-05): stack inteira + UI no painel + wiring (coordinator/watcher por sessão; PSK segue rotação; cliente usa host resolvido). 151 testes verdes, app assina. UAT T47 em 2 macs: aceitações 1,2,4,7,8 do spec (3/5/6 já automatizadas) — **dá p/ juntar com T28 (input-polish) e T38 (discovery-pairing) numa sessão só**. Race conhecida: transferir durante rotação de pareamento falha 1× (janela ~2 s). Spikes soltos: T44 (promise-paste, opcional), T48 (drag real, gate E2).
- [x] Golden vectors → `.specs/protocol/vectors/v0_1.txt` (provados por teste).
- [ ] Spike T2 (CGEventPost fora da main thread + Esc em REMOTE) — valida na prática durante T15/UAT.
- [ ] Pairing code em JSON plano → migrar para Keychain pós-MVP.
- [x] ~~Assinatura ad-hoc: TCC re-pedindo após rebuild~~ — RESOLVIDO (beta.3): identidade self-signed "CrossDesk Dev" no keychain da máquina de build, make-app.sh auto-detecta (fallback ad-hoc). Cert Apple Developer real continua desejável p/ notarização (elimina o passo do xattr).
- [ ] **discovery-pairing — código completo (T29–T37), só falta UAT (T38)** (2026-07-04, beta.9 publicada p/ o UAT): descoberta Bonjour + token curto + rotação PAIR_SET/PAIR_ACK implementados e provados em loopback (110 testes, incertezas 1 e 3 do design mortas em teste real). Falta rodar em 2 macs: aceitações 1–8 do spec (visibilidade, pareamento, rotação persistida, esquecer, Rede Local negada→concedida — incerteza 2, fallback IP, regressão). Build 10. Segredo rotacionado herda a pendência do Keychain (acima). Dá para juntar T38 com o T28 (UAT input-polish) numa sessão só de 2 macs.
- [ ] **input-polish — código completo (T19–T27), só falta UAT (T28)** (2026-07-03). 99 testes verdes, app assina OK. Falta rodar em 2 macs: invisibilidade visual, sleep-survival (`swift run conceal-spike --sleep-test`), momentum em apps, decisão do coalescing (dormente), latência p95. Detalhes em `.specs/features/input-polish/tasks.md` T28.
  - ~~Cursor visível parado na borda~~ → R17 (`CursorConcealer`, API privada `SetsCursorInBackground` provada no spike T19).
  - ~~Seta anda após standby/wake~~ → R18 (`CursorSentinel` watchdog) + R19 (`SystemStateObserver` reassert).

## Lições (cont.)

- Simular a posição do cursor remoto no servidor (duas contabilidades da mesma verdade) drifta assim que as resoluções diferem — quem injeta o cursor é a única fonte de verdade da posição dele.
- Adicionar campo não-opcional a um `Codable` persistido (config.json) quebra o load de configs antigos (falta a chave → decode throws) — `ConfigStore` trata throw como "corrompido". Cura: `init(from:)` com `decodeIfPresent ?? default` (tolerante a chaves ausentes, mantém throw só p/ JSON inválido). Feito no `concealCursor`.
- `NSEvent.addGlobalMonitorForEvents` exige **Accessibility**, não Input Monitoring — por isso o watchdog do cliente (que só tem Accessibility p/ injetar) usa poll de `CGEvent(source: nil)?.location` a 4 Hz em vez de um monitor global: zero prompt de TCC novo.
- Notificações de wake/sessão (`NSWorkspace.didWake…`) chegam no `NSWorkspace.shared.notificationCenter`, **não** no `.default` — assinar no center errado = observer que nunca dispara.
- App menubar-only (LSUIElement): usuário pode arrastar o status item pra fora e o macOS PERSISTE a remoção → app roda sem UI alcançável para sempre. `MenuBarExtra(isInserted:)` pinado + heal do flag no launch (T17).

- `Data.removeFirst`/slices deslocam `startIndex` — subscript absoluto (`data[0]`) trapa depois. Parser de stream: sempre indexar relativo a `startIndex` e compactar com `Data(dropFirst)`. (Pegou no `FileChannelDecoder`; testes de frame-inteiro-por-feed não pegam — só o teste byte-a-byte pegou.)
- `NWConnection` presa em `.preparing` (porta morta) nunca vira `.failed` sozinha — timeout de handshake é obrigatório em UDP/DTLS (vale igual p/ TCP/TLS: `FileChannelConnection` reusa o mesmo timeout).
- Enfileirar `send()` público (queue.async) de dentro de um bloco já na queue = mensagem sai depois do teardown. Métodos internos *OnQueue diretos.
- **Confirmado na prática (beta.1→beta.2):** update de app ad-hoc quebra TCC nas duas máquinas — toggle aparece ligado em System Settings mas o preflight falha, e re-conceder NÃO regrava a entrada. Cura: `tccutil reset All dev.crossdesk.mac` + conceder de novo. Prevenção: identidade de assinatura estável.

## Lições

- (vazio)

## Preferences

- (herda da raiz)
