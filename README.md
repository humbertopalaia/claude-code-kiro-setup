# Claude Code AWS Setup — Skill para Kiro / Claude Code

Uma **Skill** que transforma seu agente de IA (Kiro, Claude Code, Cursor) em um assistente de onboarding para configurar o Claude Code com **Claude Platform on AWS**.

Em vez de seguir um tutorial manualmente, você pede ao agente "configura o Claude Code com AWS" e ele:
1. Verifica pré-requisitos (AWS CLI, Node.js, Claude Code CLI)
2. Pergunta os dados do seu time (SSO URL, Account ID, Workspace ID, etc.)
3. Cria o profile SSO
4. Faz o login
5. Configura o `~/.claude/settings.json`
6. Limpa variáveis de ambiente conflitantes
7. Instala a extensão na IDE
8. Valida que tudo funciona

Funciona em **Windows** (PowerShell) e **macOS/Linux**.

## Instalação

Copie esta pasta para dentro do diretório de skills do seu agente:

```bash
# Kiro (por projeto)
git clone https://github.com/humbertopalaia/claude-code-kiro-setup.git .kiro/skills/claude-code-aws-setup

# Kiro (global, todos os projetos)
git clone https://github.com/humbertopalaia/claude-code-kiro-setup.git ~/.kiro/skills/claude-code-aws-setup

# Claude Code standalone
git clone https://github.com/humbertopalaia/claude-code-kiro-setup.git ~/.claude/skills/claude-code-aws-setup
```

## Uso

Depois de instalar, abra o Kiro (ou Claude Code) e peça:

> "Configura o Claude Code com AWS"

O agente vai te guiar pelo processo, pedindo as informações necessárias do seu time.

## Script standalone (alternativa sem agente)

Se preferir rodar sem agente, use o script PowerShell diretamente:

```powershell
# Edite os parâmetros no início do arquivo OU passe via linha de comando:
.\scripts\setup-dev.ps1 `
    -WorkspaceId "wrkspc_XXXXXXXXXXXXXXXXXXXXXXXX" `
    -Region "us-east-2" `
    -SsoStartUrl "https://identitycenter.amazonaws.com/ssoins-XXXXXXXX" `
    -SsoRegion "us-east-1" `
    -AccountId "123456789012" `
    -SsoRoleName "MyTeam-ClaudeCode"
```

## O que você precisa do admin

Antes de rodar (seja via skill ou script), tenha em mãos:

| Dado | Exemplo |
|------|---------|
| SSO Start URL | `https://identitycenter.amazonaws.com/ssoins-XXXXXXXX` |
| SSO Region | `us-east-1` |
| Account ID (12 dígitos) | `123456789012` |
| Permission Set (Role Name) | `MyTeam-ClaudeCode` |
| Workspace ID | `wrkspc_XXXXXXXXXXXXXXXXXXXXXXXX` |
| Workspace Region | `us-east-2` |

## Estrutura

```
├── SKILL.md              ← Instruções que o agente lê e executa
├── scripts/
│   └── setup-dev.ps1     ← Script PowerShell standalone (alternativa)
└── README.md             ← Este arquivo
```

## Licença

MIT
