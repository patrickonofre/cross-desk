# ADR-001: Stack tecnológica — Rust com codebase única

**Status:** Superada por [ADR-002](#adr-002-apps-nativas-separadas-por-os-macos-primeiro-em-swift)
**Data:** 2026-07-03

## Contexto

Construir um novo software KVM multiplataforma (macOS, Windows, Linux) no espírito do Barrier, com arquitetura servidor/cliente, otimizado (latência) e fácil (configuração). Questão central: **uma tecnologia para os 3 sistemas ou implementação nativa por sistema?**

## Pesquisa — estado da arte (jul/2026)

| Projeto | Stack | Status | Observações |
|---|---|---|---|
| Barrier | C++/Qt | **Morto** (2021) | Mantenedores saíram, criaram o Input Leap |
| Input Leap | C++/Qt | **Inativo** | Fork do Barrier, estagnou |
| Deskflow | C++/Qt6, CMake | **Ativo** (v1.26.0, fev/2026, 27k stars) | Upstream oficial do Synergy; Wayland OK; protocolo compatível com todos os forks; GPL-2.0 |
| Lan Mouse | Rust, GTK4 | **Ativo** | DTLS via webrtc-rs sobre UDP; libei no Wayland; backends nativos win/mac; GPL-3.0 |
| rkvm / freemouse | Rust | Nichados | Provam viabilidade do ecossistema Rust |

**Fato decisivo:** nenhum player do mercado (nem os comerciais — Synergy, ShareMouse; nem Apple Universal Control, que é single-vendor) usa três codebases nativas separadas. Todos usam núcleo único + camada fina por plataforma. A parte inerentemente nativa (captura/injeção de input) é ~15% do código; os outros ~85% (protocolo, rede, criptografia, config, state machine de bordas, clipboard) são idênticos nos 3 sistemas.

## APIs de plataforma obrigatórias (iguais em qualquer stack)

| Plataforma | Captura | Injeção | Permissões/riscos |
|---|---|---|---|
| Windows | `WH_KEYBOARD_LL`/`WH_MOUSE_LL` + Raw Input | `SendInput` | Baixo atrito |
| macOS | `CGEventTap` (Quartz) | `CGEventPost` | TCC: Input Monitoring + Accessibility; **exige code signing estável** (tap é silenciosamente desabilitado se a assinatura muda) + notarização |
| Linux Wayland | `libei` (GNOME ≥45, Plasma ≥6.1) ou layer-shell (wlroots) | `libei`, `wlr-virtual-pointer`, ou `uinput` | Fragmentação por compositor; portal RemoteDesktop como fallback |
| Linux X11 | `XRecord`/XI2 | `XTest` | Maduro e simples |

## Decisão

**Rust, codebase única, arquitetura em camadas:**

```
┌────────────────────────────────────────────┐
│  GUI: Tauri 2 (config drag-and-drop + tray)│
├────────────────────────────────────────────┤
│  Core (compartilhado, ~85%)                │
│  protocolo · QUIC/DTLS · mDNS discovery    │
│  state machine de bordas · clipboard · cfg │
├────────────────────────────────────────────┤
│  trait InputCapture / trait InputEmulate   │
├──────────────┬──────────────┬──────────────┤
│ win (windows-│ mac (core-   │ linux (reis/ │
│ rs oficial)  │ graphics,    │ libei, x11rb,│
│              │ objc2)       │ evdev/uinput)│
└──────────────┴──────────────┴──────────────┘
```

- **Linguagem:** Rust. Sem GC/runtime (latência previsível), memory safety em código que roda com privilégios de input (superfície sensível de segurança), bindings maduros para as 3 plataformas (`windows-rs` é oficial da Microsoft; `objc2`/`core-graphics` para macOS; `reis` para libei), binário único pequeno, cross-compilation sólida.
- **Transporte:** UDP com criptografia — QUIC (`quinn`, datagrams) ou DTLS (`webrtc-rs`, validado pelo Lan Mouse). Decidir no design da feature de rede. TCP descartado para eventos de input (head-of-line blocking = travadas de cursor sob perda de pacote — defeito conhecido do Synergy/Barrier).
- **Discovery:** mDNS (`mdns-sd`) para pareamento automático na LAN.
- **GUI:** Tauri 2 — tray + janela de configuração com layout de telas drag-and-drop. Nativo o suficiente nos 3 sistemas (WebView do SO, binário pequeno), e a GUI fica isolada do core (core funciona headless via CLI/daemon). GTK4 (escolha do Lan Mouse) descartado: aparência/integração ruim em mac/win.

## Alternativas rejeitadas

- **Nativo ×3 (Swift + C#/WinUI + GTK):** 3 codebases, protocolo implementado 3 vezes, drift de comportamento, custo de manutenção proibitivo. Zero precedente no mercado.
- **C++/Qt6:** é exatamente o Deskflow, que já existe, é maduro e ativo. Recriar do zero em C++ não agrega; se a escolha fosse C++/Qt, o racional seria contribuir para o Deskflow, não criar projeto novo.
- **Go:** captura/injeção exigiria cgo pesado em tudo; ecossistema de input fraco (robotgo); GC.
- **Electron/JS puro:** incapaz de captura global de input sem native modules; pesado; sobra só a UI — que o Tauri resolve melhor.

## Consequências

- (+) Um protocolo, um core testável em CI num único job por OS, features chegam nas 3 plataformas simultaneamente.
- (+) Diferencial real sobre Deskflow (C++ de ~20 anos, TCP) e Lan Mouse (GUI GTK fraca fora do Linux, macOS imaturo).
- (−) Wayland continua sendo o maior risco técnico (fragmentação de compositores) — mitigado seguindo o caminho já validado pelo Lan Mouse (libei + fallbacks).
- (−) macOS exige conta Apple Developer para signing/notarização já no MVP.
- (−) Time precisa de fluência em Rust.

---

# ADR-002: Apps nativas separadas por OS — macOS primeiro, em Swift

**Status:** Aceita (decisão do usuário, 2026-07-03)
**Data:** 2026-07-03
**Supera:** ADR-001

## Contexto

Após o veredito da ADR-001 (Rust, codebase única), o usuário questionou a viabilidade de apps nativas separadas e decidiu seguir esse caminho: **uma app nativa por sistema operacional**, começando pelo macOS em **Swift 100% nativo** (opção híbrida Rust core + Swift UI foi apresentada e descartada).

## Decisão

1. **Três apps independentes**, uma por OS, cada uma com stack nativa e ciclo próprio de specs (`macos/`, futuramente `windows/` e `linux/`).
2. **macOS primeiro**: Swift + SwiftUI (`MenuBarExtra`), CGEventTap/CGEventPost, Network.framework, CryptoKit, `SMAppService` para autostart.
3. **Protocolo de rede neutro e versionado** em [.specs/protocol/PROTOCOL.md](../protocol/PROTOCOL.md) — contrato único que as três implementações devem cumprir. Keycodes em **USB HID Usage IDs** (neutro entre CGKeyCode/mac, scancodes/win, evdev/linux).
4. **Vetores de teste dourados** (golden test vectors) no repositório: bytes de mensagens canônicas que toda implementação valida em teste de conformidade — mitigação principal contra drift de protocolo entre as 3 codebases.

## Consequências

- (+) Fidelidade máxima por plataforma (menubar real no mac, sem WebView, binário mínimo, look-and-feel nativo).
- (+) Cada app evolui e é distribuída de forma independente.
- (−) **Custo aceito conscientemente:** protocolo e lógica de bordas/estado implementados 3×; cada feature de rede/comportamento custa ~3× para chegar às três plataformas; risco de drift — mitigado pelos itens 3 e 4.
- (−) Três toolchains e pipelines de CI (Xcode/Swift, .NET ou C++, e stack Linux a definir).
- A ADR-001 permanece no histórico como registro da análise; a arquitetura em camadas (core/UI desacoplados) continua válida DENTRO de cada app nativa.
