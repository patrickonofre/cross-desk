# CrossDesk macOS

App nativa macOS do CrossDesk (ver [visão geral](../../../.specs/project/PROJECT.md) e [ADR-002](../../../.specs/project/TECH-DECISION.md)). **Implementação de referência** do [protocolo](../../../.specs/protocol/PROTOCOL.md).

## Stack

- Swift 5.10+, SwiftUI (`MenuBarExtra`) — app de menubar, sem Dock.
- Captura: `CGEventTap` (Quartz Event Services). Injeção: `CGEventPost`.
- Rede: Network.framework (`NWConnection`/`NWListener` com DTLS sobre UDP).
- Persistência de config: JSON em `~/Library/Application Support/CrossDesk/`.
- Autostart: `SMAppService` (pós-MVP).
- Alvo mínimo: **macOS 14 (Sonoma)**.
- Estrutura: app Xcode fina + lógica em Swift Packages locais (testáveis via `swift test`).

## Objetivos da app

1. Servidor e cliente na mesma app (papel escolhido na UI).
2. MVP mac↔mac: validar captura, injeção, protocolo e transporte de ponta a ponta.
3. Servir de referência viva do protocolo para as futuras apps Windows/Linux (golden vectors nascem aqui).

## Permissões (TCC)

- **Input Monitoring** — capturar eventos globais (servidor).
- **Accessibility** — postar eventos (cliente).
- Onboarding guiado na primeira execução; app funciona degradada até conceder.
