<#
.SYNOPSIS
    Chase Cowork -- minimal install.

.DESCRIPTION
    What this does:
      1. Installs Node.js (needed by the Microsoft 365 MCP server)
      2. Installs Claude Desktop via winget
      3. Writes %APPDATA%\Claude\claude_desktop_config.json with the
         company's MCP server bindings (Microsoft 365 today; Chase
         Internal MCP will be added when Phase 5 ships)
      4. Pre-installs the MS-365 MCP npm package so first launch is fast

    What this does NOT do (intentionally):
      - Does not download agent prompts. Agents are distributed via the
        Anthropic Team workspace as shared Projects. Sign in, see them.
      - Does not copy SharePoint files. SharePoint stays the source of
        truth for SOPs / project knowledge; Claude reads them through
        the MS-365 MCP at runtime.
      - Does not install Claude Code (CLI). Add -IncludeClaudeCode for
        the power-user CLI install in addition.

.PARAMETER IncludeClaudeCode
    Also install Claude Code (CLI) - the agentic terminal interface.
    Use for: Chase, Alex, anyone running multi-step agentic workflows.

.NOTES
    Distributed via public Gist:
      https://gist.github.com/grantdozier/d940862d23d72cb71cecc3d2d35a36bc
    The one-liner Chase sends to new employees:
      iex "& { $(irm 'https://gist.githubusercontent.com/grantdozier/d940862d23d72cb71cecc3d2d35a36bc/raw/quickstart.ps1') }"

    Resilient by design:
      - Window never closes silently. Read-Host pauses at every exit path.
      - Full transcript saved to Desktop\cowork-install.log.
      - All native command calls (winget, npm) wrapped to survive PS 5.1's
        $ErrorActionPreference='Stop' + stderr-as-error interaction.
#>

[CmdletBinding()]
param(
    [switch]$IncludeClaudeCode
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
    Write-Host "Takes ~3 minutes. Windows may ask for permission to install programs - say yes." -ForegroundColor DarkGray
    Write-Host ""

    # 1. Node.js (required by the Softeria MS-365 MCP server)
    Write-Host "[1/4] Verifying Node.js..." -ForegroundColor Cyan
    if (-not (Test-CommandExists 'node')) {
        Write-Host "      Installing Node 20 LTS via winget..." -ForegroundColor Yellow
        $null = Invoke-Native { winget install --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements }
        # Refresh PATH so we can use npm in this same session
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not (Test-CommandExists 'node')) {
            Write-Host "      ERR  Node still not on PATH after install. Open a new PowerShell window and re-run." -ForegroundColor Red
            Pause-And-Exit 1
        }
    }
    Write-Host "      OK   Node $(node --version)" -ForegroundColor Green

    # 2. Claude Desktop
    Write-Host "[2/4] Verifying Claude Desktop..." -ForegroundColor Cyan
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

    # 3. Company MCP config -> %APPDATA%\Claude\claude_desktop_config.json
    Write-Host "[3/4] Configuring Claude Desktop with company cloud connections..." -ForegroundColor Cyan
    $cfgDir   = Join-Path $env:APPDATA 'Claude'
    $cfgPath  = Join-Path $cfgDir 'claude_desktop_config.json'
    $cacheDir = Join-Path $env:LOCALAPPDATA 'chase-cowork'
    $tokenPath = Join-Path $cacheDir 'ms365-token-cache.json'
    New-Item -ItemType Directory -Force -Path $cfgDir   | Out-Null
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

    # Build the company's MCP servers (parsed as objects so ConvertTo-Json
    # handles JSON escaping once, no backslash double-escape).
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
        # Future: 'chase-internal' added here when Phase 5 ships.
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
    Write-Host "      OK   $cfgPath" -ForegroundColor Green

    # 4. Pre-install MS-365 MCP package for fast first launch
    Write-Host "[4/4] Pre-installing Microsoft 365 connector..." -ForegroundColor Cyan
    $mcpExit = Invoke-Native { npm install -g '@softeria/ms-365-mcp-server@0.107.2' }
    if ($mcpExit -ne 0) {
        Write-Host "      WARN npm exit code $mcpExit (deprecation warnings are usually fine)" -ForegroundColor Yellow
    } else {
        Write-Host "      OK   cached for fast first launch" -ForegroundColor Green
    }

    # Optional: Claude Code (CLI) for power users
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
    Write-Host "  2. Sign in with your Anthropic account."
    Write-Host "     You should be invited to the Chase Group Construction Team workspace."
    Write-Host "     If you don't see the invite, ask Chase."
    Write-Host "  3. In the Projects sidebar, you'll see the shared company agents:"
    Write-Host "       Email Agent, PM Agent, Operator, Onboarding."
    Write-Host "     Pick one to start a conversation focused on that area, or just start"
    Write-Host "     a default chat for general use."
    Write-Host "  4. The first time you ask Claude about your mail / calendar / SharePoint,"
    Write-Host "     a Microsoft sign-in popup appears. Approve it with your"
    Write-Host "     @chasegroupcc.com account."
    Write-Host ""
    Write-Host "Try asking:" -ForegroundColor White
    Write-Host '  "What is on my calendar today?"' -ForegroundColor DarkGray
    Write-Host '  "Find emails from Mitchell Rotolo about FPK this week."' -ForegroundColor DarkGray
    Write-Host '  "Show me what is in the 25-116 800 E Farrel folder."' -ForegroundColor DarkGray
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
