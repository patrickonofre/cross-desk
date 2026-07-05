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

- **2026-07-05 — layout-ux especificada e aprovada pelo usuário**: UX espacial no lugar do formulário — mini-mapa vivo no painel, janela "Telas" com monitores locais reais (`Displays` + `CGDisplayIsBuiltin`) e peer como tile abstrato arrastável (4 lados → `edgeSide`), estados vivos (foco/travessia/transferência), ícone dinâmico. Pesquisa: UC (travessia = onboarding), Synergy 3 (canvas livre), grade Synergy1/Deskflow = anti-padrão (#4173). Zero mudança de protocolo (§5 vira feature: peer abstrato). R35–R42 em `.specs/features/layout-ux/`. Mockup interativo apresentado na sessão. Ideia adiada: canvas bilateral em escala (exigiria geometria no fio).

- **2026-07-04 — discovery-pairing especificada** (viabilidade confirmada): descoberta Bonjour nativa (`NWListener.Service` + `NWBrowser`, `_crossdesk._udp`, zero deps) + pareamento por token curto (8 chars, ~40 bits) com rotação para segredo 128-bit via PAIR_SET/PAIR_ACK (0x05/0x06) dentro do túnel DTLS. Decisões do usuário: token curto+rotação, reconexão automática, fallback manual por IP mantido. Risco aceito: brute-force offline do token na janela de pareamento (documentar no PROTOCOL.md; PAKE elimina na Fase 4). Docs: `.specs/features/discovery-pairing/` (spec/context/design/tasks T29–T38).

## Decisões (cont. 3)

- **2026-07-05 — code review profundo de todo o CrossDeskKit/App** (168 arquivos-fonte, ~6.4k linhas — cobertura completa, não amostragem): 8 bugs reais corrigidos, todos com teste ou build de verificação; suite subiu de 166 → 168 testes verdes; release build (`make-app.sh`) limpo, zero warnings. Nenhuma lacuna de escopo pendente identificada nesta passada — próxima revisão profunda só faz sentido após a próxima leva de features (Fase 2/3) ou se surgir um bug em campo. Achados:
  - `DTLSClient.remoteHost()` lia `connection` fora da `queue` de confinamento (data race) — agora `queue.sync`.
  - `ServerBrowser.restart()` podia reviver o browser depois de um `stop()` (retry de 1s agendado antes do stop, sem guarda) — contador de geração incrementado no `stop()`.
  - `TransferCoordinator.updateFilePSK` reconstruía o listener sem retry — mesma classe de falha (bind race, EADDRINUSE) já resolvida no `DTLSServer`, mas o file-channel ficava mudo até reiniciar a app. Retry com backoff + guarda `stopped`/rotação superada.
  - `TransferCoordinator.receiveNow()` não checava `active == nil` — clicar "Receber agora" durante outra transferência descartava a oferta pendente silenciosamente.
  - `AppState.connect(to:)` gravava `config.pairedServerName` ANTES do PAIR_SET confirmar — se o usuário digitasse o token errado ou a troca falhasse, o secret antigo ficava associado ao nome errado. Agora `pendingServerName` só vira `pairedServerName` no callback `onPairSet`.
  - `Message.hello` e `FileChannelMessage.error`: truncagem de nome/mensagem por contagem de bytes (`utf8.prefix(N)`) podia cortar um caractere multi-byte ao meio (acento comum em nome de Mac). O lado receptor falha `String(data:encoding:.utf8)` e o `decodeAll` derruba o datagrama INTEIRO, não só o campo — silencioso. Fix: `WireStrings.utf8Prefix` (Sources/Protocol/Message.swift) recua byte a byte até achar um limite de escalar válido. Testes de regressão com "á" repetido no boundary exato (`MessageTests.testHelloNameTruncationNeverSplitsAMultiByteCharacter`, `FileChannelMessageTests.testErrorMessageTruncationNeverSplitsAMultiByteCharacter`).
  - `NetworkInfo.localIPv4Addresses()`: `String(cString:)` sobre `[CChar]` é a via deprecated (warning no build release) — trocado para a variante de ponteiro (`withUnsafeBufferPointer`).
  - `FileReceiver.handle`: `var item` sem mutação (warning) → `let`.
- **2026-07-05 — beta.10 publicada (build 11), tag `v0.1.0-beta.10`**: bundle inclui, além dos fixes do code review acima, as duas features code-complete que nunca tinham ganhado build/tag próprios — file-transfer E1 (T39–T46) e layout-ux (T49–T56), ambas herdadas da beta.9 (build 10). É o "build novo" do passo 0 do roteiro [UAT-2026-07-06.md](UAT-2026-07-06.md) — UATs T38/T47/T57/T28 continuam pendentes (sessão de 2 macs), rodar contra este build.

## Pendências

- [ ] **layout-ux — CODE-COMPLETE (T49–T56 ✅), falta UAT T57** (2026-07-05): DeskModel (projeção/snap/fases, unit) + janela "Telas" (canvas real + tile do peer arrastável) + mini-mapa no painel + ícone dinâmico + coach-mark R39 + a11y inline. 166 testes verdes (+15), app assina. UAT T57 em 2 macs (aceitações R35–R41 + Accessibility Inspector) — **juntar com a sessão consolidada de 2026-07-06** (T28/T38/T47). Veto pendente do usuário no UAT: símbolo `cursorarrow.motionlines` p/ REMOTE.
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
- Truncar `String.utf8` por contagem de bytes (`.prefix(N)`) pode cortar um escalar multi-byte ao meio — o outro lado falha `String(data:encoding:.utf8)` no fragmento e o parser (que confia em "UTF-8 inválido = payload corrompido") derruba a mensagem INTEIRA, não só o campo truncado. Qualquer campo de string com limite de tamanho no fio precisa recuar até um limite de escalar válido, não só cortar bytes (`WireStrings.utf8Prefix`, 2026-07-05).
- Padrão "listener/browser que se recria sozinho após falha" (retry, bind race, rotação de PSK) precisa de um contador de geração comparado no callback assíncrono — sem isso, um `stop()` chamado entre o agendamento do retry e sua execução deixa o componente reviver depois de "parado". Já resolvido no `DTLSServer` desde o início; replicado em `ServerBrowser` e `TransferCoordinator` nesta revisão (2026-07-05) — vale como checklist para qualquer novo listener nas fases 2/3.

## Lições

- (vazio)

## Preferences

- (herda da raiz)
