# STATE — CrossDesk (raiz)

## Decisões

- **2026-07-03 — ADR-002: apps nativas separadas por OS** (decisão do usuário, supera ADR-001/Rust). macOS primeiro, Swift 100% nativo, pasta `macos/`. Protocolo neutro versionado + golden vectors como contrato entre apps. Racional em [TECH-DECISION.md](TECH-DECISION.md).
- **2026-07-03 — Protocolo próprio**, sem compatibilidade Synergy/Barrier na v1.
- **2026-07-03 — Keycodes em USB HID Usage IDs** no fio (neutro entre CGKeyCode/scancode/evdev).
- **2026-07-03 — Geometria independente por máquina** (protocolo §5): resolução/layout nunca trafegam; cliente detecta a própria borda de retorno (LEAVE_REQUEST 0x12). Vale para todas as implementações (Windows/Linux herdam o contrato).

## Bloqueios

- Nenhum.

## Pendências

- [ ] Conta Apple Developer (signing/notarização) — necessária antes de distribuir a app mac; dev local funciona com assinatura ad-hoc estável.
- [ ] Definir nome final do produto (working title: CrossDesk).
- [ ] ADRs de stack para Windows e Linux (na abertura das fases 2 e 3).

## Lições

- CGEventTap no macOS é silenciosamente desabilitado se a assinatura do binário mudar entre builds — signing estável desde o dev local.

## Preferences

- Usuário fala português; respostas em modo caveman ultra (skill /caveman).
- Trabalho por app na pasta da app (`macos/.specs/`); raiz guarda visão, protocolo e decisões cross-app.
