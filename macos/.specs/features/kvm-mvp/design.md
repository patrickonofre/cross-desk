# Design — kvm-mvp

## Estrutura do código

```
macos/
├── CrossDesk.xcodeproj          # casca: app menubar, assets, entitlements, Info.plist
├── CrossDesk/                   # target da app (SwiftUI, mínimo)
│   ├── CrossDeskApp.swift       # @main, MenuBarExtra
│   ├── MenuBarView.swift        # UI (R11)
│   └── AppState.swift           # ObservableObject: papel, status, config
└── CrossDeskKit/                # SPM package local — TODA a lógica, testável headless
    ├── Package.swift
    ├── Sources/
    │   ├── Protocol/            # encoder/decoder das mensagens (R5, R15)
    │   │   ├── Message.swift    # enum Message + encode/decode (little-endian)
    │   │   └── HIDKeycodes.swift# tabela CGKeyCode ↔ HID usage (página 0x07)
    │   ├── Transport/           # DTLS/UDP (R9, R10)
    │   │   ├── DTLSServer.swift # NWListener + NWProtocolTLS(UDP)
    │   │   ├── DTLSClient.swift # NWConnection + reconexão/backoff
    │   │   └── PairingKey.swift # código de pareamento → HKDF → PSK (CryptoKit)
    │   ├── Server/
    │   │   ├── InputCapture.swift   # CGEventTap (R1)
    │   │   ├── EdgeDetector.swift   # geometria de bordas + cursor virtual (R2, R3)
    │   │   ├── EmergencyEscape.swift# Esc 3× (R4)
    │   │   └── ServerSession.swift  # state machine LOCAL ⇄ REMOTE
    │   ├── Client/
    │   │   ├── InputInjector.swift  # CGEventPost + clamp (R6)
    │   │   ├── PressedKeys.swift    # rastreio p/ key-up sintético (R7)
    │   │   └── ClientSession.swift
    │   ├── Config/              # ConfigStore JSON (R13)
    │   └── Permissions/         # preflight/request TCC (R12)
    └── Tests/
        ├── ProtocolTests/       # golden vectors (R15)
        ├── EdgeDetectorTests/
        └── PressedKeysTests/
```

Casca Xcode importa `CrossDeskKit`. `swift test` roda no package sem GUI — gate de CI local.

## State machine do servidor

```
        cursor cruza borda mapeada
 LOCAL ────────────────────────────▶ REMOTE
   ▲    ENTER(x,y) · tap suprime      │
   │                                  │ eventos → encode → DTLS
   │  cursor virtual atinge borda     │
   │  oposta · LEAVE · tap libera     │
   └──────────────────────────────────┘
        (também: Esc 3×, desconexão, stop — sempre → LOCAL)
```

- Em REMOTE, o tap continua recebendo eventos locais mas os **suprime** (retorna NULL no callback) e os converte em mensagens.
- Cursor virtual: servidor acumula deltas para saber onde o cursor "está" na tela do cliente (usando geometria normalizada) — é assim que detecta a borda de retorno (protocolo §5).
- `CGEventTap` roda em thread própria com `CFRunLoop`; timeout do tap (`kCGEventTapDisabledByTimeout`) → re-enable imediato + log.

## Fluxo de dados (servidor em REMOTE)

```
CGEventTap ─▶ ServerSession ─▶ Message.encode ─▶ DTLSServer.send (UDP)
 (thread tap)   (serial queue)                      (Network.framework queue)
```

Cliente espelhado: `DTLSClient.receive ─▶ Message.decode ─▶ ClientSession ─▶ InputInjector (main thread não é necessária; CGEventPost é thread-safe com tap próprio... **verificar no spike T2** — incerteza flagrada)`.

## Decisões técnicas

| Área | Decisão | Nota |
|---|---|---|
| DTLS | ✅ **Spike T1 passou**: `NWParameters(dtls:udp:)` + `sec_protocol_options_add_pre_shared_key`, cipher `TLS_PSK_WITH_AES_128_GCM_SHA256`, DTLS 1.2 pinado | Sem certificados — PSK derivada do código de pareamento (protocolo §1). Código-prova em `macos/spikes/dtls-spike/` |
| Pareamento | Servidor gera código (32 hex chars = 128 bits, `SecRandomCopyBytes`); PSK = HKDF-SHA256 via CryptoKit | Código copiável na UI; digitado 1× no cliente; persiste em config |
| Supressão de eventos | Tap `kCGEventTapOptionDefault` + retorno NULL | Exige Input Monitoring **e** é o motivo de a app não poder ser sandboxed (App Store fora do escopo) |
| Injeção | `CGEventPost(.cghidEventTap, ...)` | Exige Accessibility (`CGRequestPostEventAccess`) |
| Keymap | Tabela estática CGKeyCode↔HID (~120 entradas, fonte: HID Usage Tables + Apple `Events.h`) | Teclas mortas/acentos funcionam porque trafegamos keycodes físicos, não caracteres |
| Latência (R14) | Coalescing zero no MVP: 1 evento de tap = 1 mensagem; Nagle não existe em UDP | Medição: timestamp no evento + log p95 |

## Incertezas flagradas (verificar em spike, não assumir)

1. ~~**T1 — DTLS handshake**~~ ✅ RESOLVIDA (2026-07-03): DTLS-PSK funciona no Network.framework; QUIC fallback não necessário. Prova em `macos/spikes/dtls-spike/`.
2. **T2 — CGEventPost fora da main thread** — documentação ambígua; testar postar da queue de rede vs bouncing pra main.
3. **Esc 3× com tap suprimindo** — garantir que o próprio servidor vê Esc mesmo em REMOTE (o tap vê tudo antes de suprimir — deve funcionar; confirmar).

## Traceabilidade

R1→`InputCapture` · R2,R3→`EdgeDetector`+`ServerSession` · R4→`EmergencyEscape` · R5,R15→`Protocol/` · R6→`InputInjector` · R7→`PressedKeys` · R8→`Message.hello` · R9→`Transport/` · R10→`DTLSClient` · R11→`MenuBarView` · R12→`Permissions/` · R13→`Config/` · R14→medição no UAT
