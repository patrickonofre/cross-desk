# CrossDesk

Compartilhamento de teclado e mouse entre computadores via rede (software KVM, sem vídeo) — sucessor espiritual do [Barrier](https://github.com/debauchee/barrier). Um computador é o **servidor** (dono do teclado/mouse); os outros são **clientes**. O cursor cruza a borda da tela e passa a controlar a outra máquina.

**Status:** MVP macOS em validação (mac ↔ mac). Windows e Linux nas próximas fases.

## Arquitetura

Apps nativas independentes por sistema operacional ([ADR-002](.specs/project/TECH-DECISION.md)), unidas por um protocolo binário neutro e versionado:

- [`.specs/protocol/PROTOCOL.md`](.specs/protocol/PROTOCOL.md) — o contrato: UDP + DTLS-PSK, framing little-endian, keycodes em USB HID Usage IDs.
- [`.specs/protocol/vectors/`](.specs/protocol/vectors/) — golden test vectors que toda implementação deve satisfazer.
- [`macos/`](macos/) — app macOS (Swift, menubar). Implementação de referência.
- `windows/`, `linux/` — futuras.

## App macOS

Requisitos: macOS 14+, Xcode 16+.

```bash
# testes (51, headless)
cd macos/CrossDeskKit && swift test

# build da app
macos/Scripts/make-app.sh
open macos/build/CrossDesk.app
```

Permissões necessárias (System Settings → Privacidade e Segurança):

- **Servidor:** Monitoramento de Entrada
- **Cliente:** Acessibilidade

Uso: no servidor, escolha a borda e copie o código de pareamento + endereço exibidos no painel; no cliente, informe endereço e código, Iniciar nos dois. **Esc 3× devolve o controle ao servidor sempre** (mesmo com a rede caída).

## Especificações

Projeto guiado por specs (`.specs/` na raiz e em cada app): visão, ADRs, roadmap, spec/design/tasks por feature.
