# CrossDesk

## Visão

Software KVM (compartilhamento de teclado e mouse via rede, sem vídeo) multiplataforma — macOS, Windows e Linux — sucessor espiritual do Barrier (projeto morto desde 2021). Um computador atua como **servidor** (onde teclado/mouse estão conectados) e os demais como **clientes**; o cursor flui entre as telas como se fossem um único desktop.

## Objetivos

1. **Otimizado**: latência de input imperceptível (transporte UDP, sem head-of-line blocking do TCP usado por Synergy/Barrier).
2. **Fácil**: configuração servidor/cliente sem fricção — descoberta automática na LAN, GUI com layout de telas drag-and-drop, pareamento simples.
3. **Seguro por padrão**: todo tráfego criptografado (DTLS ou QUIC), sem modo texto-plano.
4. **Multiplataforma de verdade**: suporte de primeira classe a macOS (Apple Silicon + Intel), Windows 10+, Linux (Wayland **e** X11).

## Não-objetivos (v1)

- Compartilhamento de vídeo/tela.
- Suporte a Android/iOS (futuro possível).
- Compatibilidade de protocolo com Synergy/Barrier/Deskflow (protocolo próprio, moderno).
- Arrastar arquivos entre máquinas (clipboard de texto/imagem sim, drag-and-drop de arquivos depois).

## Decisão de stack

Ver [TECH-DECISION.md](TECH-DECISION.md) — **ADR-002: apps nativas separadas por OS** (decisão do usuário). macOS primeiro, em Swift 100% nativo (`macos/`); Windows e Linux depois, cada uma com stack própria. Protocolo de rede neutro e versionado em [.specs/protocol/PROTOCOL.md](../protocol/PROTOCOL.md) — contrato único entre as três apps. ADR-001 (Rust codebase única) superada, mantida como histórico.

## Referências de mercado

- [Deskflow](https://github.com/deskflow/deskflow) — upstream do Synergy, C++/Qt6, GPL-2.0, ativo.
- [Lan Mouse](https://github.com/feschber/lan-mouse) — Rust, GTK4, DTLS/UDP, GPL-3.0, ativo.
- [Input Leap](https://github.com/input-leap/input-leap) — fork do Barrier, inativo.
- [Barrier](https://github.com/debauchee/barrier) — morto (sem manutenção desde 2021).
