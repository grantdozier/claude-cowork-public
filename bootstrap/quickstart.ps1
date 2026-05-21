<#
.SYNOPSIS
    Chase Cowork -- minimal install. Includes Phase 5 chase-internal MCP.

.DESCRIPTION
    What this does:
      1. Installs Node.js (needed by the ms-365 MCP server)
      2. Installs Python 3.11 (needed by the chase-internal MCP server)
      3. Installs Claude Desktop via winget
      4. Downloads the chase-internal MCP server source
         to %LOCALAPPDATA%\chase-cowork\mcp-servers\chase-internal\
         and pip-installs its requirements
      5. Writes %APPDATA%\Claude\claude_desktop_config.json with both
         MCP server bindings (ms-365 + chase-internal)
      6. Auto-detects the user's @chasegroupcc.com SMTP via `whoami /upn`
         and sets CHASE_INTERNAL_USER in the MCP env block
      7. Pre-installs the MS-365 MCP npm package so first launch is fast

    What this does NOT do (intentionally):
      - Does not download agent prompts. Agents are distributed via the
        Anthropic Team workspace as shared Projects.
      - Does not copy SharePoint files. Claude reads them through the
        MS-365 MCP at runtime when relevant.
      - Does not install Claude Code (CLI). Pass -IncludeClaudeCode for that.

    Side note on chase-internal auth (Phase 5):
      The MCP server uses DefaultAzureCredential -> Azure Key Vault -> SQL.
      That means each user needs to be `az login`ed to Azure AND granted
      `Key Vault Secrets User` access on `kv-chase-cowork-5f74` plus
      `db_datareader` on `chasecowork-audit` for the corpus MCP to work.
      Until Chase grants those, the chase-internal MCP will return
      "Access denied" for that user. The install puts the files in place;
      the per-user Azure grants are separate manual work.

.PARAMETER IncludeClaudeCode
    Also install Claude Code (CLI) -- the agentic terminal interface.
    Use for: Chase, Alex, anyone running multi-step agentic workflows.

.PARAMETER User
    Override the auto-detected SMTP address. Useful if `whoami /upn`
    returns something other than the user's @chasegroupcc.com address.

.NOTES
    Distributed via public Gist:
      https://gist.github.com/grantdozier/d940862d23d72cb71cecc3d2d35a36bc
#>

[CmdletBinding()]
param(
    [switch]$IncludeClaudeCode,
    [string]$User
)

$ErrorActionPreference = 'Stop'

# --- Transcript log ---------------------------------------------------------
$LogPath = Join-Path $env:USERPROFILE 'Desktop\cowork-install.log'
$transcriptStarted = $false
try {
    Start-Transcript -Path $LogPath -Force -IncludeInvocationHeader | Out-Null
    $transcriptStarted = $true
} catch {
    Write-Host "(transcript could not start: $($_.Exception.Message))" -ForegroundColor DarkYellow
}

# --- Helpers ----------------------------------------------------------------
function Pause-And-Exit ([int]$code = 0) {
    Write-Host ""
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
        Write-Host "Full log saved to:" -ForegroundColor DarkGray
        Write-Host "  $LogPath" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "Press Enter to close this window..." -ForegroundColor Cyan
    [void](Read-Host)
    exit $code
}

function Invoke-Native ([scriptblock]$cmd) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $cmd; return $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
}

function Test-CommandExists ([string]$name) {
    $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    # Refresh PATH in this session so freshly winget-installed tools are usable
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

# --- Main -------------------------------------------------------------------
try {
    Write-Host ""
    Write-Host "Chase Cowork - Install" -ForegroundColor White
    Write-Host "======================" -ForegroundColor White
    if ($IncludeClaudeCode) {
        Write-Host "Mode: HYBRID (Claude Desktop + Claude Code CLI)" -ForegroundColor White
    } else {
        Write-Host "Mode: DESKTOP (Claude Desktop only - default)" -ForegroundColor White
    }
    Write-Host "Takes ~5 minutes. Windows may ask for permission to install programs - say yes." -ForegroundColor DarkGray
    Write-Host ""

    # 0. Determine user SMTP (used by chase-internal MCP for identity)
    if (-not $User) {
        try { $upn = (whoami /upn 2>$null | Select-Object -First 1).Trim() } catch { $upn = '' }
        if ($upn -match '@chasegroupcc\.com$') {
            $User = $upn
        } else {
            $User = ''
            Write-Host "[!] Could not auto-detect your @chasegroupcc.com address." -ForegroundColor Yellow
            Write-Host "    The chase-internal MCP will still install but you may need to" -ForegroundColor Yellow
            Write-Host "    edit $env:APPDATA\Claude\claude_desktop_config.json afterward and" -ForegroundColor Yellow
            Write-Host "    set CHASE_INTERNAL_USER to your @chasegroupcc.com address." -ForegroundColor Yellow
            Write-Host ""
        }
    }
    if ($User) { Write-Host "Detected user: $User" -ForegroundColor DarkGray }
    Write-Host ""

    # 1. Node.js (required by the ms-365 MCP)
    Write-Host "[1/6] Verifying Node.js..." -ForegroundColor Cyan
    if (-not (Test-CommandExists 'node')) {
        Write-Host "      Installing Node 20 LTS via winget..." -ForegroundColor Yellow
        $null = Invoke-Native { winget install --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements }
        Refresh-Path
        if (-not (Test-CommandExists 'node')) {
            Write-Host "      ERR  Node still not on PATH after install. Open a new PowerShell window and re-run." -ForegroundColor Red
            Pause-And-Exit 1
        }
    }
    Write-Host "      OK   Node $(node --version)" -ForegroundColor Green

    # 2. Python 3.11 (required by the chase-internal MCP)
    Write-Host "[2/6] Verifying Python..." -ForegroundColor Cyan
    if (-not (Test-CommandExists 'python')) {
        Write-Host "      Installing Python 3.11 via winget..." -ForegroundColor Yellow
        $null = Invoke-Native { winget install --id Python.Python.3.11 --silent --accept-source-agreements --accept-package-agreements }
        Refresh-Path
        if (-not (Test-CommandExists 'python')) {
            Write-Host "      ERR  Python still not on PATH after install. Open a new PowerShell window and re-run." -ForegroundColor Red
            Pause-And-Exit 1
        }
    }
    Write-Host "      OK   $(python --version 2>&1)" -ForegroundColor Green

    # 3. Claude Desktop
    Write-Host "[3/6] Verifying Claude Desktop..." -ForegroundColor Cyan
    $desktopInstalled = $false
    try {
        $check = & winget list --id Anthropic.Claude --accept-source-agreements 2>$null | Out-String
        if ($check -match 'Anthropic.Claude') { $desktopInstalled = $true }
    } catch { }

    if (-not $desktopInstalled) {
        Write-Host "      Installing Claude Desktop via winget..." -ForegroundColor Yellow
        $null = Invoke-Native { winget install --id Anthropic.Claude --silent --accept-source-agreements --accept-package-agreements }
        Write-Host "      OK   Claude Desktop installed" -ForegroundColor Green
    } else {
        Write-Host "      OK   already installed" -ForegroundColor Green
    }

    # 4. Download chase-internal MCP server + install its Python deps
    Write-Host "[4/6] Deploying chase-internal MCP server (Phase 5)..." -ForegroundColor Cyan
    $mcpRoot = Join-Path $env:LOCALAPPDATA 'chase-cowork\mcp-servers\chase-internal'
    New-Item -ItemType Directory -Force -Path $mcpRoot | Out-Null

    $mcpBase = 'https://raw.githubusercontent.com/grantdozier/claude-cowork-public/main/mcp-servers/chase-internal'
    foreach ($f in @('server.py', 'requirements.txt')) {
        Invoke-WebRequest -Uri "$mcpBase/$f" -OutFile (Join-Path $mcpRoot $f) -UseBasicParsing
    }
    Write-Host "      OK   downloaded server.py + requirements.txt to $mcpRoot" -ForegroundColor Green

    Write-Host "      Installing Python deps (mcp, azure-identity, azure-keyvault-secrets, pymssql)..." -ForegroundColor Yellow
    $pipExit = Invoke-Native { python -m pip install --quiet --user --upgrade -r (Join-Path $mcpRoot 'requirements.txt') }
    if ($pipExit -ne 0) {
        Write-Host "      WARN pip returned $pipExit (deprecation/warning noise is usually OK)" -ForegroundColor Yellow
    } else {
        Write-Host "      OK   Python deps installed" -ForegroundColor Green
    }

    # 5. Company MCP config -> %APPDATA%\Claude\claude_desktop_config.json
    Write-Host "[5/6] Configuring Claude Desktop..." -ForegroundColor Cyan
    $cfgDir   = Join-Path $env:APPDATA 'Claude'
    $cfgPath  = Join-Path $cfgDir 'claude_desktop_config.json'
    $cacheDir = Join-Path $env:LOCALAPPDATA 'chase-cowork'
    $tokenPath = Join-Path $cacheDir 'ms365-token-cache.json'
    New-Item -ItemType Directory -Force -Path $cfgDir   | Out-Null
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

    $chaseInternalServer = Join-Path $mcpRoot 'server.py'

    $companyServers = [ordered]@{
        'ms-365' = [pscustomobject]@{
            command = 'npx'
            args    = @('-y', '@softeria/ms-365-mcp-server@0.107.2', '--org-mode')
            env     = [pscustomobject]@{
                MS365_MCP_CLIENT_ID        = 'e2b1eeec-0b7b-4238-8bac-92007530bd31'
                MS365_MCP_TENANT_ID        = 'afbb8ea1-0e42-4f9a-b3d8-6fc556a1ea38'
                MS365_MCP_TOKEN_CACHE_PATH = $tokenPath
            }
        }
        'chase-internal' = [pscustomobject]@{
            command = 'python'
            args    = @($chaseInternalServer)
            env     = [pscustomobject]@{
                CHASE_INTERNAL_USER = $User
            }
        }
    }

    # Merge with any user-added servers without clobbering them
    $merged = [ordered]@{}
    foreach ($k in $companyServers.Keys) { $merged[$k] = $companyServers[$k] }
    if (Test-Path $cfgPath) {
        try {
            $existing = Get-Content $cfgPath -Raw | ConvertFrom-Json
            if ($existing.mcpServers) {
                foreach ($prop in $existing.mcpServers.PSObject.Properties) {
                    if (-not $merged.Contains($prop.Name)) {
                        $merged[$prop.Name] = $prop.Value
                    }
                }
            }
        } catch {
            Write-Host "      WARN existing config unparseable -- replacing" -ForegroundColor Yellow
        }
    }
    [pscustomobject]@{ mcpServers = $merged } | ConvertTo-Json -Depth 10 | Out-File $cfgPath -Encoding UTF8 -Force
    Write-Host "      OK   wrote $cfgPath" -ForegroundColor Green
    Write-Host "           - ms-365         (Microsoft 365: mail, calendar, SharePoint, OneDrive)" -ForegroundColor DarkGray
    Write-Host "           - chase-internal (Phase 5 corpus access)" -ForegroundColor DarkGray
    if ($User) {
        Write-Host "           - CHASE_INTERNAL_USER = $User" -ForegroundColor DarkGray
    } else {
        Write-Host "           - CHASE_INTERNAL_USER is EMPTY -- edit the config to set it" -ForegroundColor Yellow
    }

    # 6. Pre-install MS-365 MCP package for fast first launch
    Write-Host "[6/6] Pre-installing Microsoft 365 connector..." -ForegroundColor Cyan
    $null = Invoke-Native { npm install -g '@softeria/ms-365-mcp-server@0.107.2' }
    Write-Host "      OK   cached for fast first launch" -ForegroundColor Green

    # Optional: Claude Code CLI for power users
    if ($IncludeClaudeCode) {
        Write-Host ""
        Write-Host "[+] Installing Claude Code (CLI, power-user mode)..." -ForegroundColor Cyan
        if (-not (Test-CommandExists 'claude')) {
            $null = Invoke-Native { npm install -g '@anthropic-ai/claude-code' }
        }
        if (Test-CommandExists 'claude') {
            Write-Host "    OK   Claude Code installed - open a NEW terminal and type 'claude'" -ForegroundColor Green
        } else {
            Write-Host "    WARN Claude Code install did not complete" -ForegroundColor Yellow
        }
    }

    # Finale
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host " Install complete." -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host ""
    Write-Host "  1. Open " -NoNewline
    Write-Host "Claude" -ForegroundColor Yellow -NoNewline
    Write-Host " from the Start menu (or look for the Claude icon)."
    Write-Host "  2. Sign in with your Anthropic account (Chase Group Construction Team workspace)."
    Write-Host "  3. The first time you ask Claude about your mail / calendar / SharePoint,"
    Write-Host "     a Microsoft sign-in popup appears. Approve it with your"
    Write-Host "     @chasegroupcc.com account."
    Write-Host "  4. In the Projects sidebar you'll see the shared company agents"
    Write-Host "     (Email Agent, PM Agent, Operator) -- managed by Chase."
    Write-Host ""
    Write-Host "Phase 5 (corpus access) note:" -ForegroundColor White
    Write-Host "  The chase-internal MCP is installed. To USE it, you also need:" -ForegroundColor DarkGray
    Write-Host "    - 'az login' once (so Python can pull the SQL creds from Key Vault), and" -ForegroundColor DarkGray
    Write-Host "    - Chase to grant you 'Key Vault Secrets User' on kv-chase-cowork-5f74" -ForegroundColor DarkGray
    Write-Host "      and read access on the chasecowork-audit database." -ForegroundColor DarkGray
    Write-Host "  Until those are in place the corpus queries return 'Access denied'." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Try asking:" -ForegroundColor White
    Write-Host '  "What is on my calendar today?"' -ForegroundColor DarkGray
    Write-Host '  "Find emails from Mitchell Rotolo about FPK this week."' -ForegroundColor DarkGray
    Write-Host '  "Give me my daily briefing."  (uses chase-internal)' -ForegroundColor DarkGray
    Write-Host '  "What is overdue?"            (uses chase-internal)' -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Stuck? Message Chase. The full install log is at:"
    Write-Host "  $LogPath" -ForegroundColor DarkGray
    Pause-And-Exit 0

} catch {
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Red
    Write-Host " INSTALL FAILED" -ForegroundColor Red
    Write-Host "==============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Where it happened:" -ForegroundColor DarkGray
    Write-Host "$($_.ScriptStackTrace)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Send Chase the log file at:" -ForegroundColor Yellow
    Write-Host "  $LogPath" -ForegroundColor DarkGray
    Pause-And-Exit 1
}
