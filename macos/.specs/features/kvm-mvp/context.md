# Context — kvm-mvp (decisões de gray areas)

Decisões assumidas pelo agente com defaults sensatos (usuário pode reverter qualquer uma; custo de mudança indicado):

| # | Gray area | Decisão | Racional | Custo de reverter |
|---|-----------|---------|----------|-------------------|
| 1 | Alvo mínimo de macOS | **14 (Sonoma)** | MenuBarExtra/SMAppService estáveis; 2 versões atrás da atual | Baixo (baixar p/ 13) |
| 2 | Uma app ou duas (servidor/cliente)? | **Uma app, papel via toggle** | UX simples, binário único, código compartilhado | Médio |
| 3 | Transporte: DTLS vs QUIC | **DTLS** (`NWProtocolTLS` sobre UDP), QUIC como fallback | Datagrama puro, menor overhead; validado pelo Lan Mouse (DTLS) | Baixo se spike T1 falhar (design isola transporte) |
| 4 | Confiabilidade de KEY/MOUSE_BUTTON sobre UDP | **Aceitar perda no MVP** (protocolo §5) | LAN tem perda ~0; canal confiável adia complexidade | Médio (v0.2 do protocolo) |
| 5 | Formato de config | **JSON + Codable** | Nativo Swift, zero dependência | Trivial |
| 6 | Atalho de emergência | **Esc 3× em 1 s** | Não conflita com apps; funciona mesmo com tap ativo | Trivial (configurável depois) |
| 7 | Assinatura em dev | **Ad-hoc estável (mesmo certificado local)** | CGEventTap é desabilitado silenciosamente se assinatura mudar; conta Apple Developer só na distribuição | — |
| 8 | Múltiplos monitores | **Servidor: suporta (borda na tela onde está o cursor). Cliente: só tela principal** | Corta metade da complexidade de geometria | Médio (pós-MVP) |

Nenhuma dessas travava o início; se alguma estiver errada, ajustar aqui e refletir em spec/design.
