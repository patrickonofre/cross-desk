# Roadmap — CrossDesk (apps nativas por OS, ADR-002)

## Fase 0 — Protocolo neutro

- [PROTOCOL.md](../protocol/PROTOCOL.md) v0.1: framing, tipos de mensagem, keycodes HID, criptografia.
- Golden test vectors (bytes canônicos) para conformidade entre implementações.
- Evolui junto com a Fase 1 (a app mac é a implementação de referência).

## Fase 1 — App macOS (Swift) ← ATUAL

- Pasta [macos/](../../macos/), specs próprias em `macos/.specs/`.
- MVP: servidor + cliente na mesma app, mac↔mac, transporte UDP criptografado, menubar UI mínima.
- Detalhes e milestones em `macos/.specs/project/ROADMAP.md`.

## Fase 2 — App Windows

- Stack candidata: C# (.NET/WinUI 3) + hooks/SendInput via P/Invoke. ADR própria na hora.
- Gate de fase: interop mac↔win validada contra PROTOCOL.md + golden vectors.

## Fase 3 — App Linux

- Stack a definir (Qt ou GTK; libei/Wayland + XTest/X11). ADR própria na hora.
- Gate de fase: interop com mac e win.

## Fase 4 — Facilidade e polish (cross-app)

- Discovery mDNS + pareamento com código curto — **adiantado para a Fase 1** na app mac (feature `discovery-pairing`, 2026-07-04); Windows/Linux herdam o contrato (PROTOCOL.md §7 + PAIR_SET/PAIR_ACK). Resta na Fase 4: upgrade PAKE (SPAKE2).
- Clipboard sincronizado (texto/imagem).
- Empacotamento e distribuição: dmg notarizado, msi/winget, AppImage/flatpak.
- Auto-update por plataforma.

## Ideias adiadas

- ~~Drag-and-drop de arquivos entre máquinas~~ — **antecipado para a Fase 1** (feature `file-transfer`, 2026-07-04): E1 = ⌘C/⌘V de arquivos mac↔mac; E2 = drag real condicionado a spike. Specs em `macos/.specs/features/file-transfer/`.
- Android/iOS como cliente.
- Modo compatibilidade com protocolo Synergy/Barrier (avaliar demanda).
