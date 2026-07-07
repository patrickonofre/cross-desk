# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/); versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [1.1.1] - 2026-07-07

### Fixed

- Ajustes internos de estabilidade, sem mudança de comportamento para o usuário.

## [1.1.0] - 2026-07-07

### Added

- Aviso de nova versão disponível: o app checa periodicamente os Releases do GitHub e mostra um rótulo discreto no popover quando há uma versão mais nova, com botão para abrir a página de download. Instalação continua manual — sem auto-instalação.

## [1.0.0] - 2026-07-07

### Added

- App macOS (menubar): compartilhamento de teclado/mouse entre dois Macs (KVM sem vídeo), transporte UDP criptografado (DTLS-PSK), Esc 3× devolve o controle sempre (mesmo com a rede caída).
- Descoberta automática na rede local (Bonjour) + pareamento por token curto, com rotação para um segredo de 128 bits após o primeiro handshake.
- Transferência de arquivos entre as máquinas pareadas via ⌘C/⌘V.
- Ocultação do cursor na máquina sem foco, com trava contra deriva e recuperação automática após sleep/wake/troca de monitor.
- Mini-mapa vivo no painel e janela "Telas" para posicionar visualmente o outro Mac (arrastar define a borda de travessia).
- Abrir o CrossDesk automaticamente ao iniciar sessão (opcional).

### Fixed

- Robustez contra VPN corporativa interferindo na sessão local — o transporte recusa rotear por interfaces de túnel, sempre prioriza a LAN física.
- Encerramento do app restrito aos dois caminhos deliberados (botão "Sair" e relançamento após conceder permissão), evitando fechamentos inesperados por bugs do SwiftUI (Apple FB11447959) ou comandos implícitos do sistema.
