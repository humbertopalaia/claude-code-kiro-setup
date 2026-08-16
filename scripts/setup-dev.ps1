<#
.SYNOPSIS
    Configura o Claude Code para usar o Claude Platform on AWS.

.DESCRIPTION
    Roda na maquina de cada desenvolvedor. Faz:
      1. Valida a versao da AWS CLI
      2. Faz login SSO
      3. Grava/mescla ~/.claude/settings.json com as variaveis do provider
      4. Remove CLAUDE_CODE_USE_BEDROCK e CLAUDE_CODE_USE_FOUNDRY (tem precedencia)
      5. Valida o acesso ao workspace

    Nao altera nada na conta AWS. Somente configuracao local.

.PARAMETER Profile
    Nome do profile SSO. Default: claude-platform. Criado pelo script se nao existir.

.EXAMPLE
    .\setup-dev.ps1
    .\setup-dev.ps1 -Profile meu-profile-sso

.NOTES
    ANTES DE USAR: Preencha os valores dos parametros abaixo com os dados
    fornecidos pelo administrador AWS do seu time.
#>

[CmdletBinding()]
param(
    [string]$Profile     = "claude-platform",

    # ============================================================
    # PREENCHA COM OS DADOS DO SEU TIME (peca ao admin AWS)
    # ============================================================
    [string]$WorkspaceId = "<SEU_WORKSPACE_ID>",          # Ex: wrkspc_XXXXXXXXXXXXXXXXXXXXXXXX
    [string]$Region      = "<REGIAO_DO_WORKSPACE>",       # Ex: us-east-2
    [string]$SsoStartUrl = "<URL_DO_IDENTITY_CENTER>",    # Ex: https://identitycenter.amazonaws.com/ssoins-XXXXXXXX
    [string]$SsoRegion   = "<REGIAO_DO_IDENTITY_CENTER>", # Ex: us-east-1
    [string]$AccountId   = "<ID_DA_CONTA_AWS>",           # Ex: 123456789012
    [string]$SsoRoleName = "<NOME_DO_PERMISSION_SET>",    # Ex: MyTeam-ClaudeCode
    # ============================================================

    [switch]$SkipInstall,
    [switch]$SkipIdeExtension
)

$ErrorActionPreference = "Stop"

function Write-Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Warn2{ param([string]$m) Write-Host "    !!  $m" -ForegroundColor Yellow }

# ---- Validacao dos parametros obrigatorios
$placeholders = @($WorkspaceId, $Region, $SsoStartUrl, $SsoRegion, $AccountId, $SsoRoleName)
if ($placeholders | Where-Object { $_ -match "^<" }) {
    throw @"
Parametros nao preenchidos!

Antes de rodar este script, preencha os valores dos parametros no bloco
'PREENCHA COM OS DADOS DO SEU TIME' no inicio do arquivo, ou passe via
linha de comando:

    .\setup-dev.ps1 -WorkspaceId "wrkspc_XXX" -Region "us-east-2" `
        -SsoStartUrl "https://..." -SsoRegion "us-east-1" `
        -AccountId "123456789012" -SsoRoleName "MeuRole"

Peca esses valores ao administrador AWS do seu time.
"@
}

# ---------------------------------------------------------------- 1. AWS CLI
Write-Step "Verificando AWS CLI"

try {
    $raw = (aws --version 2>&1 | Out-String).Trim()
} catch {
    throw "AWS CLI nao encontrada no PATH. Instale a v2: winget install Amazon.AWSCLI"
}

if ($raw -notmatch "aws-cli/(\d+)\.(\d+)\.(\d+)") {
    throw "Nao foi possivel interpretar a versao da AWS CLI: $raw"
}

$major = [int]$Matches[1]
$minor = [int]$Matches[2]

if ($major -lt 2 -or ($major -eq 2 -and $minor -lt 30)) {
    throw @"
AWS CLI muito antiga ($raw).
O comando 'aws iam enable-outbound-web-identity-federation' nao existe nela.
Atualize com:  winget upgrade --id Amazon.AWSCLI
Depois abra um terminal novo e rode este script de novo.
"@
}
Write-Ok $raw

# ---------------------------------------------------------- 1b. Claude Code
Write-Step "Verificando o Claude Code"

# o npm global bin costuma nao estar no PATH da sessao atual
$npmBin = Join-Path $env:APPDATA "npm"
if ((Test-Path $npmBin) -and ($env:Path -notlike "*$npmBin*")) {
    $env:Path = "$env:Path;$npmBin"
}

$claudeVersion = $null
if (Get-Command claude -ErrorAction SilentlyContinue) {
    $claudeVersion = (claude --version 2>&1 | Out-String).Trim()
}

if (-not $claudeVersion) {
    if ($SkipInstall) {
        throw "Claude Code nao instalado. Rode: npm install -g @anthropic-ai/claude-code"
    }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw "Claude Code nao instalado e npm ausente. Instale o Node.js LTS e rode o script de novo."
    }
    Write-Warn2 "Claude Code nao encontrado. Instalando via npm."
    npm install -g @anthropic-ai/claude-code
    if ((Test-Path $npmBin) -and ($env:Path -notlike "*$npmBin*")) {
        $env:Path = "$env:Path;$npmBin"
    }
    $claudeVersion = (claude --version 2>&1 | Out-String).Trim()
}

Write-Ok $claudeVersion

# awsAuthRefresh exige 2.1.198+
if ($claudeVersion -match "(\d+)\.(\d+)\.(\d+)") {
    $cMajor = [int]$Matches[1]; $cMinor = [int]$Matches[2]; $cPatch = [int]$Matches[3]
    $tooOld = ($cMajor -lt 2) -or
              ($cMajor -eq 2 -and $cMinor -lt 1) -or
              ($cMajor -eq 2 -and $cMinor -eq 1 -and $cPatch -lt 198)
    if ($tooOld) {
        throw @"
Claude Code anterior a 2.1.198 ($claudeVersion). Requisito, nao recomendacao:
o permission set do time tem sessao de 1 hora, e nessas versoes o 'awsAuthRefresh'
nao funciona - a cada expiracao o Claude Code para e pede /login, que nao renova
credencial AWS.

Atualize e rode este script de novo:
    npm install -g @anthropic-ai/claude-code@latest
"@
    }
}

# ------------------------------------------------------- 1c. Profile SSO
Write-Step "Verificando o profile '$Profile'"

$startUrl = (aws configure get sso_start_url --profile $Profile 2>$null)

if (-not $startUrl) {
    Write-Warn2 "Profile sem configuracao de SSO. Criando com o permission set '$SsoRoleName'."

    aws configure set sso_start_url  $SsoStartUrl --profile $Profile
    aws configure set sso_region     $SsoRegion   --profile $Profile
    aws configure set sso_account_id $AccountId   --profile $Profile
    aws configure set sso_role_name  $SsoRoleName --profile $Profile
    aws configure set region         $Region      --profile $Profile
    aws configure set output         "json"       --profile $Profile
    Write-Ok "Profile '$Profile' configurado para a conta $AccountId"
} else {
    Write-Ok "Profile ja configurado ($startUrl)"

    $currentRole = (aws configure get sso_role_name --profile $Profile 2>$null)
    if ($currentRole -and $currentRole -ne $SsoRoleName) {
        Write-Warn2 @"
O profile '$Profile' aponta para o permission set '$currentRole', nao '$SsoRoleName'.
O script nao altera profile existente. Se '$currentRole' nao for intencional, rode
de novo com outro nome de profile:
    .\setup-dev.ps1 -Profile claude-code
"@
    }
}

# ~/.aws/credentials tem precedencia sobre as chaves sso_* do ~/.aws/config.
$credFile = Join-Path $HOME ".aws\credentials"
if (Test-Path $credFile) {
    if (Select-String -Path $credFile -Pattern "^\[$([regex]::Escape($Profile))\]" -Quiet) {
        Write-Warn2 @"
Existe uma secao [$Profile] em ~/.aws/credentials.
Chaves estaticas ali tem precedencia sobre a configuracao SSO e vao sobrepor o
login, normalmente com erro 'ExpiredToken'. Remova essa secao do arquivo
(guarde um backup antes) ou use outro nome de profile via -Profile.
"@
    }
}

# ---------------------------------------------------------------- 2. Login SSO
Write-Step "Login SSO no profile '$Profile'"

$identity = $null
try {
    $identity = aws sts get-caller-identity --profile $Profile --output json 2>$null | ConvertFrom-Json
} catch { }

if (-not $identity) {
    Write-Warn2 "Sessao ausente ou expirada. Abrindo o navegador para login."
    aws sso login --profile $Profile
    $identity = aws sts get-caller-identity --profile $Profile --output json | ConvertFrom-Json
}

if ($identity.Account -ne $AccountId) {
    Write-Warn2 "Atencao: autenticado na conta $($identity.Account), mas o workspace esta na $AccountId."
}

Write-Ok "Conta $($identity.Account) como $($identity.Arn)"

# ---------------------------------------------------------------- 3. settings.json
Write-Step "Configurando ~/.claude/settings.json"

$claudeDir    = Join-Path $HOME ".claude"
$settingsPath = Join-Path $claudeDir "settings.json"

if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

$settings = [ordered]@{}
if (Test-Path $settingsPath) {
    $backup = "$settingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $settingsPath $backup
    Write-Warn2 "settings.json existente. Backup em: $backup"
    try {
        $existing = Get-Content $settingsPath -Raw | ConvertFrom-Json
        foreach ($p in $existing.PSObject.Properties) { $settings[$p.Name] = $p.Value }
    } catch {
        Write-Warn2 "settings.json atual nao e JSON valido. Sera substituido (backup preservado)."
    }
}

# mescla o bloco env preservando chaves de outros fins
$envBlock = [ordered]@{}
if ($settings.Contains("env") -and $settings["env"]) {
    foreach ($p in $settings["env"].PSObject.Properties) { $envBlock[$p.Name] = $p.Value }
}

$envBlock["CLAUDE_CODE_USE_ANTHROPIC_AWS"] = "1"
$envBlock["ANTHROPIC_AWS_WORKSPACE_ID"]    = $WorkspaceId
$envBlock["AWS_REGION"]                    = $Region
$envBlock["AWS_PROFILE"]                   = $Profile

# Bedrock e Foundry tem precedencia sobre Claude Platform on AWS
foreach ($k in @("CLAUDE_CODE_USE_BEDROCK","CLAUDE_CODE_USE_FOUNDRY")) {
    if ($envBlock.Contains($k)) {
        $envBlock.Remove($k)
        Write-Warn2 "Removido '$k' do settings.json (tinha precedencia sobre o provider)"
    }
}

$settings["env"]            = $envBlock
$settings["awsAuthRefresh"] = "aws sso login --profile $Profile"

$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
Write-Ok "Gravado em $settingsPath"

# ---------------------------------------------------------------- 4. Variaveis de ambiente
Write-Step "Limpando variaveis que sequestram o roteamento"

$hijackers = @("CLAUDE_CODE_USE_BEDROCK","CLAUDE_CODE_USE_FOUNDRY")
$found = $false

foreach ($name in $hijackers) {
    foreach ($scope in @("Process","User")) {
        $val = [Environment]::GetEnvironmentVariable($name, $scope)
        if ($val) {
            [Environment]::SetEnvironmentVariable($name, $null, $scope)
            Write-Warn2 "Removido $name (escopo $scope, valor era '$val')"
            $found = $true
        }
    }
    $machineVal = [Environment]::GetEnvironmentVariable($name, "Machine")
    if ($machineVal) {
        Write-Warn2 "$name esta definido em escopo Machine ('$machineVal'). Remova como administrador:"
        Write-Host  "        [Environment]::SetEnvironmentVariable('$name', `$null, 'Machine')"
        $found = $true
    }
}

if (-not $found) { Write-Ok "Nenhuma variavel conflitante encontrada" }

# ------------------------------------------------------ 4b. Extensao de IDE
if (-not $SkipIdeExtension) {
    Write-Step "Extensao do Claude Code nas IDEs detectadas"

    $editors = [ordered]@{
        "code"   = "Code"
        "cursor" = "Cursor"
        "kiro"   = "Kiro"
    }

    $any = $false
    foreach ($cli in $editors.Keys) {
        $exe = (Get-Command $cli -ErrorAction SilentlyContinue)
        if (-not $exe) { continue }
        $any = $true

        Write-Host "    instalando em '$cli'..."
        & $exe.Source --install-extension anthropic.claude-code --force 2>&1 |
            Where-Object { $_ -match "successfully installed|already installed" } |
            ForEach-Object { Write-Ok $_.ToString().Trim() }

        $dir = Join-Path $env:APPDATA "$($editors[$cli])\User"
        $sp  = Join-Path $dir "settings.json"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $o = [ordered]@{}
        if (Test-Path $sp) {
            Copy-Item $sp "$sp.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            try {
                $cur = Get-Content $sp -Raw | ConvertFrom-Json
                foreach ($pr in $cur.PSObject.Properties) { $o[$pr.Name] = $pr.Value }
            } catch {
                Write-Warn2 "settings.json de $cli invalido. Backup feito, arquivo sera reescrito."
            }
        }
        $o["claudeCode.disableLoginPrompt"] = $true
        $o | ConvertTo-Json -Depth 10 | Set-Content $sp -Encoding UTF8
        Write-Ok "disableLoginPrompt configurado em $cli"
    }

    if (-not $any) {
        Write-Warn2 "Nenhuma IDE compativel encontrada no PATH (code, cursor, kiro). Usando somente a CLI."
    }
}

# ---------------------------------------------------------------- 5. Validacao
Write-Step "Validando acesso ao workspace"

$env:AWS_PROFILE                    = $Profile
$env:AWS_REGION                     = $Region
$env:ANTHROPIC_AWS_WORKSPACE_ID     = $WorkspaceId
$env:CLAUDE_CODE_USE_ANTHROPIC_AWS  = "1"

$fed = $null
try {
    $fed = aws iam get-outbound-web-identity-federation-info --profile $Profile --output json 2>$null | ConvertFrom-Json
} catch { }

if ($fed -and $fed.JwtVendingEnabled) {
    Write-Ok "Outbound web identity federation habilitada na conta $($identity.Account)"
} else {
    Write-Warn2 @"
Outbound web identity federation NAO parece habilitada na conta $($identity.Account).
Um administrador precisa rodar UMA VEZ, nessa conta:
    aws iam enable-outbound-web-identity-federation --profile $Profile
Sem isso as requisicoes falham com
'Outbound web identity federation is disabled for your account'.
"@
}

Write-Host @"

------------------------------------------------------------
Configuracao local concluida.

Proximo passo, neste mesmo terminal:

    claude

O banner precisa mostrar 'Claude Platform on AWS'.
Depois rode /status e confira:
    API provider : Claude Platform on AWS
    Workspace ID : $WorkspaceId
    Region       : $Region

Se aparecer 403 / AccessDenied em toda requisicao, seu usuario ainda nao
recebeu a policy de acesso. Fale com o administrador.
------------------------------------------------------------
"@ -ForegroundColor White
