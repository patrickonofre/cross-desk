# Spec — debug-console (console de log ao vivo, atalho global oculto)

**Escopo:** Medium (contido: 3 arquivos novos + wiring no `CrossDeskApp`, zero mudança de protocolo/servidor/cliente). Pipeline: spec → execute (design/tasks dispensados — <10 passos, sem decisão arquitetural em aberto após a verificação abaixo).

**Contexto:** UAT de 2026-07-06 reportou "app fechou sozinho ao conectar". Investigação via `log show` confirmou que não houve crash (sem `.ips`, sequência de `terminate:` limpa), mas expôs um buraco de observabilidade: hoje só dá pra inspecionar o unified log de fora do app (`log stream`/Console.app), depois do fato, sem saber o timestamp exato de nada em tempo real durante o próprio UAT. Esta feature dá um jeito de abrir o log ao vivo, de dentro do app, no meio de um teste — sem precisar de terminal por perto.

## Verificação técnica (Knowledge Verification Chain)

- **Atalho global sem permissão nova:** `RegisterEventHotKey` (Carbon/HIToolbox) confirmado via busca — é a única API pública de hotkey global no macOS que **não exige Accessibility**, continua funcional em macOS 14/15 (ressalva: combinações só com Option/Option+Shift têm bug conhecido no macOS 15 final — não se aplica aqui, `Cmd+Shift+D` usa Cmd+Shift+letra). `NSEvent.addGlobalMonitorForEvents` foi descartado propositalmente — exigiria Accessibility mesmo no papel servidor, que hoje só pede Input Monitoring (quebraria o modelo de permissão por papel do PROJECT.md). Sem dependência externa (mantém o padrão zero-deps do projeto) — wrapper próprio (~2 arquivos pequenos), no estilo de `PairingKey.swift`.
- **Fonte do log:** reaproveita literalmente o comando já documentado em `Logging.swift` (`log stream --predicate 'subsystem == "dev.crossdesk.mac"' --info --debug`), rodado como subprocess via `Process`/`Pipe` — mesmo padrão já usado em `AppState.relaunch()`. Alternativa `OSLogStore` (in-process) descartada: não tem push nativo (exigiria polling) e o comando de shell já é o que o próprio código recomenda para debug manual.

## Requisitos

- **R43 — Atalho global `Cmd+Shift+D`.** Registrado via `RegisterEventHotKey` no lançamento do app, ativo independente de papel (servidor/cliente), de pareamento e de qual app está em foco. Alterna (abre se fechado, fecha se aberto) o console de debug. Nenhuma permissão nova solicitada.
- **R44 — Log ao vivo no console.** Uma janela mostra, em tempo real, a saída de `log stream --predicate 'subsystem == "dev.crossdesk.mac"' --info --debug` (subprocess `Process`/`Pipe`, uma linha por evento). Latência alvo: linha aparece na UI em <1s do evento.
- **R45 — Sem rastro nenhum de UI.** Nenhuma entrada em `MenuBarView`, nenhum item de Dock, nenhuma menção fora do código-fonte e desta spec — descobrível só por quem sabe o atalho. Presente em **todos** os builds, incluindo release assinado via `make-app.sh` (não é `#if DEBUG`) — é o build que roda em UAT real.
- **R46 — Janela flutuante, fechável.** Nível `.floating` (fica acima de outras apps — o cenário de uso é observar o log enquanto o foco de input está na outra máquina). Fecha pelo botão padrão da janela ou repetindo `Cmd+Shift+D`.
- **R47 — Buffer limitado.** Máximo 2000 linhas em memória (FIFO — descarta as mais antigas). Uma sessão de KVM longa não pode crescer sem limite nem degradar a UI.
- **R48 — Ações mínimas.** Botões "Limpar" (zera o buffer) e "Copiar tudo" (pasteboard) — o mínimo pra ser útil colando num relato de bug.
- **R49 — Filtro por texto (P2, não-MVP).** Campo de busca simples (substring, case-insensitive) sobre as linhas já bufferizadas — não precisa reiniciar o stream.

## Fora de escopo

| Item | Motivo |
| --- | --- |
| Log da máquina peer (a outra ponta da sessão) | Cada Mac só tem acesso ao seu próprio unified log — logging cross-machine exigiria um canal novo no protocolo, fora do problema que esta feature resolve. |
| Atalho configurável pelo usuário | Feature é oculta/uso interno (Patrick), não precisa de UI de preferências pra isso — trocar a combinação é uma linha de código se incomodar. |
| Filtrar por nível (info/debug/error) na UI | `--info --debug` já traz tudo que o app loga; filtro de nível vira ruído extra sem necessidade concreta ainda. |
| Persistir o log em arquivo | Buffer em memória (R47) resolve o caso de uso (UAT ao vivo); exportar pra arquivo é trivial de adicionar depois se aparecer a necessidade. |

## Aceitação (UAT)

1. Com o app rodando em qualquer papel, pareado ou não, `Cmd+Shift+D` com **outro app em foco** (ex.: Finder) abre o console flutuante imediatamente.
2. Iniciar servidor, tentar conectar, erro de permissão, PAIR_SET — cada ação aparece no console em menos de 1s.
3. `Cmd+Shift+D` de novo fecha o console; abrir de novo depois não crasha nem duplica o subprocesso `log stream` (checar `ps aux | grep log` — só uma instância).
4. Fechar pelo botão padrão da janela também encerra o subprocesso (mesmo check de `ps`).
5. Sessão de KVM ativa por alguns minutos com tráfego intenso de log não trava a UI nem cresce memória sem limite.
6. O `.app` assinado por `make-app.sh` (build usado no UAT real) tem a feature disponível sem flag ou build separado.
7. Nenhuma pista da feature aparece em `MenuBarView` (menu normal do app permanece idêntico ao de hoje).

## Decisões assumidas (fácil de mudar se incomodar)

- Combinação exata: `Cmd+Shift+D`. Risco aceito de colidir com atalho local de outro app em foco (ex.: Safari usa `Cmd+Shift+D` pra "Adicionar Bookmarks de todas as abas") — como o hotkey é global, tem prioridade sobre o atalho local do app frontmost nesse instante. Aceitável por ser feature oculta/uso interno; trocar a tecla é mudança de uma linha.
- Janela `.floating` (sempre acima) por padrão — se atrapalhar no dia a dia, vira `.normal` fácil.
- Buffer de 2000 linhas — ajustável, é uma constante.
- R49 (filtro de texto) entra já na primeira implementação se o custo for baixo; não é bloqueante pra fechar a feature.
