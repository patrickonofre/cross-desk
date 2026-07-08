# Spec — sparkle-auto-update (auto-instalação real, substitui update-check)

**Escopo:** Large (dependência nova, mudança de build/assinatura, infra de hospedagem,
processo de release). Pipeline completo: spec → design → tasks → execute.

**Contexto:** `update-check` (v1.1.0) avisa versão nova mas exige o usuário abrir o GitHub e
instalar manualmente. Decisão anterior (`update-check/spec.md`) foi explicitamente NÃO usar
Sparkle "por enquanto" — motivo: sem Xcode project, sem infra de assinatura/appcast, e
incidente de TCC quebrando ao trocar bundle. Usuário pediu agora replicar exatamente o
mecanismo do `mac-metrics-view` (Sparkle completo: framework embutido, appcast.xml hospedado,
EdDSA assinando cada release) — decisão tomada explicitamente após confronto do trade-off
(ver pergunta feita e resposta "Sparkle completo"). Bloqueio de TCC mitigado: identidade de
assinatura estável (`CrossDesk Dev`) já existe desde beta.3 (`STATE.md`), pré-condição que
faltava na época da decisão anterior.

## Goals

- [ ] Botão manual renomeado "Verificar agora" → "Verificar Atualizações".
- [ ] Clicar nele (ou a checagem automática encontrar update) baixa e instala a nova versão
      sem abrir o navegador — mesmo comportamento do mac-metrics-view.
- [ ] Checagem automática no launch + periódica via Sparkle nativo (substitui o timer manual
      de 24h do `AppState`).

## Out of Scope

| Item | Motivo |
| --- | --- |
| Geração da chave privada EdDSA pelo agente | Custódia de chave é ação do usuário — perda quebra update de todo mundo. Script preparado, execução manual. |
| Habilitar GitHub Pages / primeiro release assinado | Ação em sistema externo/visível a outros — confirmar com usuário antes. |
| Migrar pra Xcode project | Sparkle SPM funciona embutindo o `.framework` via `make-app.sh` (mesmo padrão de `codesign` manual já usado); não precisa de `.xcodeproj`. |
| Windows/Linux auto-update | Só existe app mac hoje (mesma nota do update-check). |

## User Stories

### P1: Instalação em 1 clique ⭐ MVP

**User Story**: Como usuário do CrossDesk, quero clicar em "Verificar Atualizações" e ter a
nova versão baixada, verificada e instalada sem sair do app.

**Acceptance Criteria**:

1. WHEN usuário clica "Verificar Atualizações" THEN Sparkle SHALL checar o appcast, e se
   houver versão mais nova, mostrar sua própria UI de download/instalação.
2. WHEN não há versão nova THEN Sparkle SHALL informar "está atualizado" (UI nativa dele).
3. WHEN o appcast está inacessível (rede/hosting fora do ar) THEN app SHALL continuar
   funcionando normalmente, sem crash (mesma regra de falha silenciosa do R61 antigo).

**Independent Test**: publicar um appcast de teste com versão fake maior, apontar
`SUFeedURL` pra ele, clicar o botão, confirmar que a UI de instalação do Sparkle aparece.

---

### P2: Aviso passivo discreto (mantém UX atual)

**User Story**: Como usuário, quero continuar vendo o rótulo discreto "Nova versão x.x.x
disponível" no popover sem a UI do Sparkle pular na cara toda vez que ele checa em
background — só quando eu agir.

**Acceptance Criteria**:

1. WHEN Sparkle encontra update em checagem automática (launch/periódica) THEN app SHALL
   mostrar só o rótulo discreto (não a UI de instalação do Sparkle).
2. WHEN usuário clica "Ignorar" no rótulo THEN a versão SHALL ficar marcada como dispensada
   (mesmo campo `AppConfig.dismissedUpdateVersion`, mesma regra de R60 antigo).
3. WHEN usuário clica "Instalar" no rótulo (ou "Verificar Atualizações") THEN Sparkle SHALL
   assumir com sua UI completa (download, verificação EdDSA, troca do bundle, relaunch).

**Independent Test**: mesmo cenário do P1, mas via checagem automática — confirmar que o
rótulo aparece sem popup do Sparkle até o clique.

---

## Requirement Traceability

| ID | Story | Status |
| --- | --- | --- |
| SPK-01 | Botão renomeado | Pending |
| SPK-02 | Dependência Sparkle (SPM) só no target `CrossDeskApp` | Pending |
| SPK-03 | `SparkleUpdateService` (probe passivo + check interativo) | Pending |
| SPK-04 | `AppState` usa `SparkleUpdateService` no lugar de `UpdateChecker.checkLatestRelease` | Pending |
| SPK-05 | `make-app.sh` embute `Sparkle.framework` + assina aninhado (XPCs/Autoupdate/Updater.app) | Pending |
| SPK-06 | `Info.plist`: `SUFeedURL`/`SUPublicEDKey`/`SUEnableAutomaticChecks`/`SUScheduledCheckInterval` | Pending |
| SPK-07 | `docs/appcast.xml` (repo root, hospedado via GitHub Pages) | Pending (infra manual) |
| SPK-08 | Script de assinatura de release (`sign_update` do Sparkle) | Pending |
| SPK-09 | Chave EdDSA gerada e custodiada pelo usuário | Pending (manual, fora do agente) |

**Coverage:** 9 total, 7 no agente (código/scripts), 2 manuais (chave, Pages/primeiro release).

## Success Criteria

- [ ] `swift build -c release --product CrossDeskApp` compila com Sparkle linkado.
- [ ] `make-app.sh` produz `.app` com `Sparkle.framework` assinado e verificável
      (`codesign --verify --deep --strict`).
- [ ] 190 testes existentes continuam verdes (menos os 5 de `checkLatestRelease`, que saem
      por não terem mais o que testar — Sparkle busca o appcast, não é código nosso).
- [ ] UAT: instalar uma versão antiga, publicar uma nova assinada, confirmar 1-clique
      atualiza sem passar pelo navegador.
