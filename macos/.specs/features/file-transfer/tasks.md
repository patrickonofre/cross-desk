# Tasks — file-transfer (E1 + spikes)

Numeração continua do projeto (última: T38). Gate padrão: `cd macos/CrossDeskKit && swift test` verde + build `macos/Scripts/make-app.sh` OK. `[P]` = paralelizável.

Status: T39–T43, T45, T46 ✅ (2026-07-05, 151 testes verdes, app assina) — **E1 code-complete**. Pendentes: T47 (UAT), T44/T48 (spikes).

- T46 notas: seção no painel (pendingOffer c/ "Receber"/dispensar, receiving c/ progresso+cancelar, sending, done c/ dica ⌘V, failed) + wiring no AppState (coordinator+watcher por sessão; cliente inicia canal no primeiro `.connected` usando host resolvido via `DTLSClient.remoteHost()`; rotação de pareamento atualiza PSK do canal dos dois lados; reveal no Finder no fluxo Downloads). SPEC_DEVIATION (menor): "ViewModel unit" — a lógica de estados vive no `TransferCoordinator` (kit, testado); AppState/View são mapeamento fino → cobertos no UAT T47. Race conhecida: transferência disparada DURANTE a rotação de pareamento falha uma vez (PSK em troca) — retry manual resolve; janela de ~2 s, uma vez por par.

- T45 notas: `TransferCoordinator` (uma transferência por vez; announce eager ≤teto / pendingOffer >teto ou ocupado; servidor recebe via FILE_PULL+push aguardado c/ timeout; staging removido em falha/cancel) + `PasteboardWatcher`/`PasteboardFacade` (`SystemPasteboard` real; marker `dev.crossdesk.transfer-id`). Sessions ganharam `onFileMessage` + `sendControl` (app liga coordinator↔session no T46). E2E loopback provado nos dois sentidos + fluxo Downloads + anti-loop.

- T43 notas: `Sources/FileTransfer/` (FileSender pull-based c/ SHA-256 incremental; FileReceiver c/ staging `.part`→rename, `materialize(into:)` c/ sufixo de colisão, `cleanStaging`). Defesas extra além do spec: symlink já em staging não pode virar componente de path de item posterior (peer hostil escaparia do staging via link — lstat por componente); raízes com mesmo nome são uniquificadas no sender.

- T41/T42 notas: `Reader` do Message.swift virou interno compartilhado (+u32/u64); `FileChannelDecoder` usa offsets relativos a `startIndex` (lição: `Data.removeFirst` desloca startIndex — subscript absoluto trapa); `FileChannelListener` NÃO retém conexões aceitas (consumidor retém até `.closed` — documentado); `PairingKey.filePSK` = HKDF `info="tls-psk-file"`.

## T39 ✅ — Protocolo: delta no PROTOCOL.md + golden vectors

- **What:** PROTOCOL.md ganha §Arquivos (tabelas D4: DTLS 0x50/0x51 + framing TCP 0x01–0x07), nota de segurança (PSK `info="tls-psk-file"`), changelog. Golden vectors novos em `.specs/protocol/vectors/` (CLIP_FILES, FILE_PULL, FILE_HELLO, ITEM_META c/ symlink, DATA, ITEM_DONE, TRANSFER_DONE, CANCEL, ERROR).
- **Where:** `.specs/protocol/PROTOCOL.md`, `.specs/protocol/vectors/`
- **Depends on:** — · **Reuses:** formato dos vectors existentes
- **Done when:** doc + vectors commitados; tipos não colidem com existentes; `proto_version` inalterado (justificado no changelog).
- **Tests:** vectors validados por teste no T41/T42.

## T40 ✅ — Spike I1: TLS-PSK sobre TCP no Network.framework `[P]`

- **What:** provar `NWListener`/`NWConnection` TCP com TLS 1.2 PSK (`sec_protocol_options_add_pre_shared_key`, suite `TLS_PSK_WITH_AES_128_GCM_SHA256`) em loopback, eco de bytes. Reprovou → plano B do D1, atualizar design.
- **Where:** `macos/spikes/tls-file-spike/`
- **Resultado (2026-07-05): SUCCESS** — handshake TLS 1.2 PSK + ping/pong + stream de 1 MiB em loopback. Mesma API do spike T1 (DTLS), pin min/max `.TLSv12`. I1 morta no design; plano B descartado. Nota: PSK do spike é string fixa — derivação real (`info="tls-psk-file"`) entra no T41 reusando `PairingKey`.
- **Depends on:** — · **Reuses:** `DTLSParameters` (espelho), `PairingKey` (HKDF)
- **Done when:** ~~handshake + eco OK em loopback~~ ✅; registrado no design e STATE.
- **Tests:** o próprio spike (executável), depois formalizado no T41.

## T41 — Transport: FileChannelListener/FileChannelConnection

- **What:** listener TCP no servidor (mesma porta numérica, ativo só com servidor ativo), connect no cliente, lifecycle por transferência (abre→HELLO→fecha), timeouts de handshake (lição NWConnection presa em `.preparing`).
- **Where:** `Sources/Transport/`
- **Depends on:** T39, T40 · **Reuses:** padrões de queue/teardown do DTLSServer/DTLSClient (lição: sends internos *OnQueue)
- **Done when:** loopback: cliente conecta, troca FILE_HELLO, fecha limpo; porta ocupada/handshake errado → erro claro sem travar sessão de input.
- **Tests:** unit loopback (handshake, timeout, teardown duplo).

## T42 — Protocol: FileChannelMessage + Message 0x50/0x51

- **What:** encode/decode do framing TCP (u32 length) + CLIP_FILES/FILE_PULL no framing DTLS; conformidade com golden vectors do T39.
- **Where:** `Sources/Protocol/`
- **Depends on:** T39 · **Reuses:** infra de encode/decode do `Message.swift`
- **Done when:** todos os vectors novos passam; fuzz leve (payload truncado/length mentiroso → erro, nunca crash).
- **Tests:** vectors + roundtrip + malformed.

## T43 — FileTransfer: FileSender + FileReceiver (pipelines)

- **What:** novo target `FileTransfer`. Sender: walk recursivo (symlink não seguido), ITEM_META/DATA(64 KiB)/ITEM_DONE, SHA-256 incremental. Receiver: staging `.part` em `~/Library/Caches/CrossDesk/incoming/<id>/`, sanitização de path (rejeita `..`/absoluto/NUL), hash check, rename atômico, colisão ` (2)`, limpeza staging >24 h no launch.
- **Where:** `Sources/FileTransfer/` novo, `Package.swift`
- **Depends on:** T42 · **Reuses:** —
- **Done when:** roundtrip em memória (sender→receiver sem rede): árvore com subpastas, symlink, arquivo 0 B, nome com unicode → destino fiel; paths maliciosos rejeitados; hash errado → item descartado + erro.
- **Tests:** unit por regra do spec (R3, R5, R7 — aceitações 3/5/6 automatizadas aqui).

## T44 — Spike I2: promise-paste no Finder `[P]` (opcional, não bloqueia)

- **What:** `NSFilePromiseProvider` no pasteboard geral: ⌘V no Finder materializa? Passou → registrar no design (lazy p/ >teto vira task futura). Falhou → teto+botão confirmado, I2 morta.
- **Where:** `macos/spikes/`
- **Depends on:** — · **Done when:** resultado binário registrado (design + STATE).

## T45 — TransferCoordinator + PasteboardWatcher

- **What:** watcher (poll 0,5 s de changeCount, só types — nunca conteúdo; anti-loop own-write via type `dev.crossdesk.transfer-id`); coordinator: máquina de estados por transfer_id (announce → eager ≤200 MB / pendente >teto → materialize → done/cancel/error), integração com ServerSession/ClientSession (CLIP_FILES/FILE_PULL) e com FileChannel (push/request).
- **Where:** `Sources/FileTransfer/`, integração em `Sources/Server/` e `Sources/Client/`
- **Depends on:** T41, T43 · **Reuses:** padrão de estados das sessions
- **Done when:** loopback E2E: copiar (simulado) numa ponta → pasteboard da outra recebe URLs após transfer; >teto → fica pendente até "receber"; anti-loop provado (announce não ecoa); cancelamento nos dois lados limpa staging.
- **Tests:** E2E loopback + unit do anti-loop e da máquina de estados.

## T46 — UI: progresso, cancelar, "Receber agora"

- **What:** seção no painel menubar: transferência ativa (nome/contagem, bytes, %, cancelar), pendente >teto ("N arquivos, X GB — Receber agora"), erro visível; reveal no Finder ao concluir p/ Downloads.
- **Where:** app (SwiftUI)
- **Depends on:** T45
- **Done when:** estados renderizam (ativo/pendente/erro/concluído); cancelar funciona; VoiceOver lê os elementos.
- **Tests:** ViewModel unit; visual no UAT.

## T47 — UAT E1 (2 macs) — aceitações 1–8 do spec

- **What:** roteiro: (1) copiar/colar pequeno nos DOIS sentidos; (2) ≥1 GB c/ progresso+cancel; (3) árvore de pastas; (4) rede caída no meio → erro limpo, sem parcial, input se recupera; (7) fluidez do input durante 1 GB (se degradar → `serviceClass = .background`, D5); (8) build antigo ignora 0x50/0x51. Aceitações 5/6 já automatizadas no T43.
- **Depends on:** T46 · **Done when:** checklist assinado no tasks.md; falhas viram tasks.

## T48 — Spike I3/S1: drag real (gate da E2) `[P]` após T43

- **What:** janela invisível sob cursor + `beginDraggingSession` com `NSFilePromiseProvider` movida por eventos injetados (critérios spec R10: inicia com evento sintético; Finder + um app comum aceitam; promise resolve pós-transferência sem travar alvo).
- **Where:** `macos/spikes/`
- **Done when:** veredito registrado (design/STATE/ROADMAP): E2 entra (especificar), degrada p/ pasta, ou morre.

## Ordem

```
T39 → T42 → T43 ─┬→ T45 → T46 → T47
T40 → T41 ───────┘
[P]: T40 c/ T39; T44 e T48 a qualquer momento (T48 após T43 p/ reusar pipeline)
```
