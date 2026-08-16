---
name: "claude-code-aws-setup"
description: "Configure Claude Code to use Claude Platform on AWS (corporate/team setup). Guides through AWS CLI verification, SSO profile creation, SSO login, ~/.claude/settings.json configuration, environment variable cleanup, IDE extension installation, and final validation. Works on Windows (PowerShell) and macOS/Linux. Use when someone asks to set up Claude Code with AWS, configure Claude Platform on AWS, or onboard a developer to use Claude Code via SSO."
---

# Claude Code - AWS Platform Setup

This skill guides developers through configuring Claude Code to use **Claude Platform on AWS** instead of a personal Anthropic account. It covers the full onboarding flow for corporate/team environments.

## When to Use

- Developer needs to set up Claude Code for the first time with AWS provider
- Developer is getting authentication errors with Claude Code on AWS
- Team is onboarding new members and needs a repeatable setup process
- Developer switched machines and needs to reconfigure

## Prerequisites Check

Before starting, verify each prerequisite. **Stop and inform the user** if any is missing.

### 1. AWS CLI (v2.30+)

Run:
```bash
aws --version
```

- Must return `aws-cli/2.X.Y` where X.Y >= 30.0
- If missing: suggest `winget install Amazon.AWSCLI` (Windows) or `brew install awscli` (macOS)
- If version too old: suggest `winget upgrade --id Amazon.AWSCLI` (Windows) or `brew upgrade awscli` (macOS)
- Why v2.30+: the `outbound-web-identity-federation` feature required by Claude Platform on AWS was introduced in this version

### 2. Node.js + npm

Run:
```bash
node --version
npm --version
```

- Node.js LTS (v18+) required
- npm comes bundled with Node.js
- If missing: suggest `winget install OpenJS.NodeJS.LTS` (Windows) or `brew install node` (macOS)

### 3. Claude Code CLI (v2.1.198+)

Run:
```bash
claude --version
```

- If missing, install: `npm install -g @anthropic-ai/claude-code`
- If version < 2.1.198, update: `npm install -g @anthropic-ai/claude-code@latest`
- Why v2.1.198+: the `awsAuthRefresh` feature (automatic credential renewal when SSO session expires) requires this version. Older versions interrupt the user every hour with a `/login` prompt.

**Windows PATH note:** If `claude` is not found after install, the npm global bin may not be in PATH for the current session. Check:
```powershell
$npmBin = Join-Path $env:APPDATA "npm"
$env:Path = "$env:Path;$npmBin"
claude --version
```

### 4. Collect Configuration from User (MANDATORY — DO NOT SKIP)

**Before proceeding to the Setup Workflow, you MUST ask the user for ALL of the following values.** These are organization-specific and cannot be guessed or defaulted. Present them as a checklist and wait for the user to provide each one:

> To configure Claude Code with your team's AWS workspace, I need the following information from your AWS administrator. Please provide:
>
> 1. **SSO Start URL** — The Identity Center URL for your organization
>    _(looks like: `https://identitycenter.amazonaws.com/ssoins-XXXXXXXX` or `https://your-org.awsapps.com/start`)_
> 2. **SSO Region** — Region where your Identity Center is hosted
>    _(e.g., `us-east-1`)_
> 3. **Account ID** — The 12-digit AWS account ID where the Claude workspace lives
>    _(e.g., `123456789012`)_
> 4. **SSO Role Name** — The permission set name that grants Claude Code access
>    _(e.g., `MyTeam-ClaudeCode`)_
> 5. **Workspace ID** — The Claude Platform workspace identifier
>    _(looks like: `wrkspc_XXXXXXXXXXXXXXXXXXXXXXXX`)_
> 6. **Workspace Region** — The AWS region where the workspace operates
>    _(e.g., `us-east-2`)_
>
> If you don't have these, ask your AWS administrator or team lead.

**Do NOT proceed until all 6 values are provided.** If the user is unsure about any value, help them understand what it is and where to find it, but do not invent or assume values.

Once collected, use these values consistently in all subsequent steps (profile creation, settings.json, validation).

---

## Setup Workflow

Execute these steps in order. Confirm each step succeeds before proceeding.

### Step 1: Create SSO Profile

Choose a profile name (default: `claude-platform`). Then configure:

```bash
aws configure set sso_start_url  "<SSO_START_URL>"  --profile <PROFILE>
aws configure set sso_region     "<SSO_REGION>"     --profile <PROFILE>
aws configure set sso_account_id "<ACCOUNT_ID>"     --profile <PROFILE>
aws configure set sso_role_name  "<SSO_ROLE_NAME>"  --profile <PROFILE>
aws configure set region         "<WORKSPACE_REGION>" --profile <PROFILE>
aws configure set output         "json"             --profile <PROFILE>
```

**Check for conflicts:** If the profile already exists, verify it points to the correct SSO role:
```bash
aws configure get sso_role_name --profile <PROFILE>
```

**Check for credential file conflicts:** Static credentials in `~/.aws/credentials` override SSO config. If a section `[<PROFILE>]` exists there, warn the user to remove it (it causes `ExpiredToken` errors even after successful SSO login).

### Step 2: SSO Login

First, check if there's already a valid session:
```bash
aws sts get-caller-identity --profile <PROFILE>
```

If that fails (session expired or absent), initiate login:
```bash
aws sso login --profile <PROFILE>
```

This opens the browser for authentication. After the user completes login, verify:
```bash
aws sts get-caller-identity --profile <PROFILE>
```

Expected output includes `Account` and `Arn` fields. Confirm the Account matches the expected Account ID.

### Step 3: Configure ~/.claude/settings.json

Create or update `~/.claude/settings.json`. **Always preserve existing settings** — merge, don't overwrite.

The required configuration:

```json
{
  "env": {
    "CLAUDE_CODE_USE_ANTHROPIC_AWS": "1",
    "ANTHROPIC_AWS_WORKSPACE_ID": "<WORKSPACE_ID>",
    "AWS_REGION": "<WORKSPACE_REGION>",
    "AWS_PROFILE": "<PROFILE>"
  },
  "awsAuthRefresh": "aws sso login --profile <PROFILE>"
}
```

**Critical:** Remove these keys from the `env` block if present (they take precedence and hijack routing):
- `CLAUDE_CODE_USE_BEDROCK`
- `CLAUDE_CODE_USE_FOUNDRY`

**Backup:** Before modifying, create a backup:
- Windows: `Copy-Item ~/.claude/settings.json ~/.claude/settings.json.bak`
- macOS/Linux: `cp ~/.claude/settings.json ~/.claude/settings.json.bak`

### Step 4: Clean Environment Variables

Check if conflicting environment variables exist:

**Windows (PowerShell):**
```powershell
[Environment]::GetEnvironmentVariable("CLAUDE_CODE_USE_BEDROCK", "User")
[Environment]::GetEnvironmentVariable("CLAUDE_CODE_USE_FOUNDRY", "User")
[Environment]::GetEnvironmentVariable("CLAUDE_CODE_USE_BEDROCK", "Process")
[Environment]::GetEnvironmentVariable("CLAUDE_CODE_USE_FOUNDRY", "Process")
```

**macOS/Linux:**
```bash
echo $CLAUDE_CODE_USE_BEDROCK
echo $CLAUDE_CODE_USE_FOUNDRY
```

If any is set, remove them:

**Windows:**
```powershell
[Environment]::SetEnvironmentVariable("CLAUDE_CODE_USE_BEDROCK", $null, "User")
[Environment]::SetEnvironmentVariable("CLAUDE_CODE_USE_FOUNDRY", $null, "User")
```

**macOS/Linux:** Remove from `~/.bashrc`, `~/.zshrc`, or equivalent shell config.

**Machine/System scope (Windows):** If set at Machine level, warn the user they need an elevated (Administrator) terminal to remove it.

### Step 5: Install IDE Extension

Detect which IDEs are available and install the Claude Code extension:

```bash
# Kiro
kiro --install-extension anthropic.claude-code --force

# VS Code
code --install-extension anthropic.claude-code --force

# Cursor
cursor --install-extension anthropic.claude-code --force
```

Then disable the login prompt (not needed with AWS provider). Add to the IDE's `settings.json`:

```json
{
  "claudeCode.disableLoginPrompt": true
}
```

IDE settings.json locations:
- **Windows:** `%APPDATA%\<IDE>\User\settings.json` (where IDE = Code, Cursor, or Kiro)
- **macOS:** `~/Library/Application Support/<IDE>/User/settings.json`
- **Linux:** `~/.config/<IDE>/User/settings.json`

### Step 6: Validate

Run Claude Code and check the banner:
```bash
claude
```

The startup banner **must** show `Claude Platform on AWS`.

Inside Claude Code, run `/status` and confirm:
- API provider: Claude Platform on AWS
- Workspace ID: matches the configured value
- Region: matches the configured value

---

## Troubleshooting

### "ExpiredToken" immediately after login
**Cause:** Static credentials in `~/.aws/credentials` with the same profile name override SSO.
**Fix:** Remove the `[<PROFILE>]` section from `~/.aws/credentials`.

### Claude Code asks for Anthropic login despite configuration
**Cause:** `settings.json` not found or malformed; or `CLAUDE_CODE_USE_ANTHROPIC_AWS` is not `"1"` (string).
**Fix:** Verify `~/.claude/settings.json` exists, is valid JSON, and has the `env` block with string value `"1"` (not boolean `true` or number `1`).

### Claude Code stops every hour asking for /login
**Cause:** Claude Code version < 2.1.198 (no `awsAuthRefresh` support).
**Fix:** `npm install -g @anthropic-ai/claude-code@latest`

### Works in terminal but not in IDE extension
**Cause:** IDE was opened before settings were configured; extension cached old state.
**Fix:** Reload window (`Ctrl+Shift+P` → "Reload Window") or restart the IDE.

### "Outbound web identity federation is disabled for your account"
**Cause:** AWS account admin hasn't enabled the federation feature.
**Fix:** Admin must run once: `aws iam enable-outbound-web-identity-federation --profile <PROFILE>`
This is a one-time account-level operation. Not something the developer can fix.

### 403 / AccessDenied on every request
**Cause:** User's IAM identity hasn't been granted access policy in the Claude Platform workspace.
**Fix:** Contact the AWS administrator to grant workspace access to the user.

---

## Automated Script

A PowerShell script (`setup-dev.ps1`) is available in the `scripts/` folder of this skill. It automates all steps above for Windows environments. Usage:

```powershell
.\setup-dev.ps1                           # Default settings
.\setup-dev.ps1 -Profile my-profile       # Custom profile name
.\setup-dev.ps1 -SkipInstall              # Skip Claude Code installation
.\setup-dev.ps1 -SkipIdeExtension         # Skip IDE extension setup
```

The script only modifies local configuration (never touches the AWS account).

## Notes

- This setup is **local only** — it configures the developer's machine, not the AWS account
- The AWS administrator is responsible for: creating the workspace, enabling federation, configuring permission sets, and granting user access
- SSO sessions typically expire every 1-8 hours (depends on the permission set). The `awsAuthRefresh` setting handles renewal automatically
- Multiple developers can share the same `setup-dev.ps1` with their team's parameters baked in
