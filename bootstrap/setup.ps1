<#
.SYNOPSIS
    Chase Cowork - hybrid platform installer for a Chase Group employee laptop.

.DESCRIPTION
    Default: installs Claude Desktop (GUI) and configures it with the company's
    Microsoft 365 MCP server. This is what every employee gets.

    With -IncludeClaudeCode: also installs Claude Code (CLI) for power users
    who want subagents, slash commands, and the full agentic workflow.

    Idempotent. Re-running upgrades versions and reapplies config.

.PARAMETER IncludeClaudeCode
    Also install Claude Code (CLI). Chase / Alex / anyone doing agentic work.

.PARAMETER SkipPrereqs
    Skip the prereq verification step (assumes Node, Git already present).

.NOTES
    ASCII-only on purpose - PowerShell 5.1 reads files without BOM in the
    system codepage, so Unicode em-dashes / box-drawing chars get corrupted.
#>

[CmdletBinding()]
param(
    [switch]$IncludeClaudeCode,
    [switch]$SkipPrereqs,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# --- Paths ------------------------------------------------------------------
$BootstrapDir   = $PSScriptRoot
$CoworkRoot     = Split-Path $BootstrapDir -Parent
$ClaudeConfig   = Join-Path $CoworkRoot 'claude-config'
$VersionsPath   = Join-Path $BootstrapDir 'versions.json'
$UserClaudeDir  = Join-Path $env:USERPROFILE '.claude'                       # Claude Code
$DesktopAppData = Join-Path $env:APPDATA 'Claude'                            # Claude Desktop
$DesktopConfigPath = Join-Path $DesktopAppData 'claude_desktop_config.json'
$ConfigTemplate = Join-Path $ClaudeConfig 'claude_desktop_config.template.json'

# --- Helpers ----------------------------------------------------------------
function Write-Step ([string]$msg) { Write-Host "  > $msg" -ForegroundColor Cyan }
function Write-Ok   ([string]$msg) { Write-Host "    OK   $msg" -ForegroundColor Green }
function Write-Warn ([string]$msg) { Write-Host "    WARN $msg" -ForegroundColor Yellow }
function Write-Err  ([string]$msg) { Write-Host "    ERR  $msg" -ForegroundColor Red }

function Test-CommandExists ([string]$name) {
    $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

# Run a native command without 2>&1. PowerShell 5.1 wraps a native command's
# stderr lines as ErrorRecord objects, and with $ErrorActionPreference='Stop'
# those terminate the script even when the command exited 0 (e.g. npm warns).
function Invoke-Native ([scriptblock]$cmd) {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $cmd
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEAP
    }
}

# --- 0. Banner --------------------------------------------------------------
Write-Host ""
Write-Host "Chase Cowork - Platform Setup" -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor White
if ($IncludeClaudeCode) {
    Write-Host "Mode: HYBRID (Claude Desktop + Claude Code)" -ForegroundColor White
} else {
    Write-Host "Mode: DESKTOP (Claude Desktop only)" -ForegroundColor White
}
Write-Host "Bootstrap dir : $BootstrapDir"
Write-Host "Desktop config: $DesktopConfigPath"
if ($IncludeClaudeCode) {
    Write-Host "Code user dir : $UserClaudeDir"
}
Write-Host ""

# --- 1. Verify the bundle is intact -----------------------------------------
Write-Step 'Verifying bundle integrity'
if (-not (Test-Path (Join-Path $ClaudeConfig 'CLAUDE.md'))) {
    Write-Err "claude-config/CLAUDE.md is missing at $ClaudeConfig"
    Write-Err 'The bootstrap bundle is incomplete. Re-run quickstart.ps1 to redownload.'
    exit 1
}
if (-not (Test-Path $ConfigTemplate)) {
    Write-Err "Desktop config template missing at $ConfigTemplate"
    exit 1
}
Write-Ok 'claude-cowork/ contents present'

# --- 2. Read versions -------------------------------------------------------
Write-Step "Reading pinned versions from versions.json"
$versions = Get-Content $VersionsPath -Raw | ConvertFrom-Json
Write-Ok "python = $($versions.python), node = $($versions.node), ms_365_mcp_server = $($versions.ms_365_mcp_server)"

# --- 3. Prereqs via winget --------------------------------------------------
if (-not $SkipPrereqs) {
    Write-Step "Verifying prereqs (Node, Git - required by the MS-365 MCP)"

    if (-not (Test-CommandExists 'node')) {
        Write-Warn 'Node not found - installing Node 20 via winget'
        $null = Invoke-Native { winget install --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements }
    } else {
        Write-Ok ('Node: ' + (node --version))
    }

    if (-not (Test-CommandExists 'git')) {
        Write-Warn 'Git not found - installing Git via winget'
        $null = Invoke-Native { winget install --id Git.Git --silent --accept-source-agreements --accept-package-agreements }
    } else {
        Write-Ok ('Git: ' + ((git --version) -replace 'git version ', ''))
    }

    if ($IncludeClaudeCode) {
        # Python + uv only needed for the full Code experience
        if (-not (Test-CommandExists 'python')) {
            Write-Warn 'Python not found - installing Python 3.11 via winget'
            $null = Invoke-Native { winget install --id Python.Python.3.11 --silent --accept-source-agreements --accept-package-agreements }
        } else {
            Write-Ok ('Python: ' + (python --version 2>&1))
        }

        if (-not (Test-CommandExists 'uv')) {
            Write-Warn 'uv not found - installing'
            $null = Invoke-Native { winget install --id astral-sh.uv --silent --accept-source-agreements --accept-package-agreements }
        } else {
            Write-Ok ('uv: ' + (uv --version))
        }
    }
} else {
    Write-Warn 'Skipping prereqs (-SkipPrereqs)'
}

# --- 4. Claude Desktop (DEFAULT) --------------------------------------------
Write-Step 'Verifying Claude Desktop installation'
$desktopInstalled = $false
try {
    $check = winget list --id Anthropic.Claude --accept-source-agreements 2>$null | Out-String
    if ($check -match 'Anthropic.Claude') { $desktopInstalled = $true }
} catch { }

if (-not $desktopInstalled) {
    Write-Warn 'Claude Desktop not found - installing via winget'
    $null = Invoke-Native { winget install --id Anthropic.Claude --silent --accept-source-agreements --accept-package-agreements }
    Write-Ok 'Claude Desktop installed'
} else {
    Write-Ok 'Claude Desktop already installed'
}

# --- 5. Generate and deploy claude_desktop_config.json ----------------------
Write-Step "Writing Claude Desktop MCP config to $DesktopConfigPath"
New-Item -ItemType Directory -Force -Path $DesktopAppData | Out-Null

# Load template, expand path sentinels
$configContent = Get-Content $ConfigTemplate -Raw
$configContent = $configContent -replace '__LOCAL_APP_DATA__', ($env:LOCALAPPDATA -replace '\\', '\\\\')

# Parse template + merge with any existing user-added MCP servers
$companyConfig = $configContent | ConvertFrom-Json
$mergedServers = @{}
foreach ($prop in $companyConfig.mcpServers.PSObject.Properties) {
    $mergedServers[$prop.Name] = $prop.Value
}

if (Test-Path $DesktopConfigPath) {
    try {
        $existing = Get-Content $DesktopConfigPath -Raw | ConvertFrom-Json
        if ($existing.mcpServers) {
            foreach ($prop in $existing.mcpServers.PSObject.Properties) {
                # Don't overwrite the company-managed servers
                if (-not $mergedServers.ContainsKey($prop.Name)) {
                    $mergedServers[$prop.Name] = $prop.Value
                }
            }
        }
    } catch {
        Write-Warn "Existing config at $DesktopConfigPath unparseable - will be replaced"
    }
}

$finalConfig = @{ mcpServers = $mergedServers }
$finalConfig | ConvertTo-Json -Depth 10 | Out-File $DesktopConfigPath -Encoding UTF8 -Force
Write-Ok 'Claude Desktop config deployed (company MCP servers merged with any existing user entries)'

# --- 6. Pre-install MS-365 MCP package so first launch is fast --------------
Write-Step "Pre-installing @softeria/ms-365-mcp-server@$($versions.ms_365_mcp_server)"
$mcpPkg = "@softeria/ms-365-mcp-server@$($versions.ms_365_mcp_server)"
$mcpExit = Invoke-Native { npm install -g $mcpPkg }
if ($mcpExit -ne 0) {
    Write-Warn "npm install returned exit code $mcpExit (deprecation warnings are usually fine)"
} else {
    Write-Ok "MS-365 MCP cached for fast first-launch"
}

# --- 7. Token cache directory ----------------------------------------------
$mcpCacheDir = Join-Path $env:LOCALAPPDATA 'chase-cowork'
New-Item -ItemType Directory -Force -Path $mcpCacheDir | Out-Null

# --- 8. OPTIONAL Claude Code install ----------------------------------------
if ($IncludeClaudeCode) {
    Write-Host ""
    Write-Step 'Installing Claude Code (CLI, for power users)'

    if (-not (Test-CommandExists 'claude')) {
        $null = Invoke-Native { npm install -g @anthropic-ai/claude-code }
        if (-not (Test-CommandExists 'claude')) {
            Write-Err 'Claude Code install failed. Install manually and rerun.'
            exit 1
        }
    }
    Write-Ok ('Claude Code: ' + (claude --version 2>&1))

    Write-Step "Mirroring claude-config/ into $UserClaudeDir (preserves Claude Code state)"
    New-Item -ItemType Directory -Force -Path $UserClaudeDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $UserClaudeDir 'subagents') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $UserClaudeDir 'skills') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $UserClaudeDir 'commands') | Out-Null

    foreach ($f in @('CLAUDE.md', 'settings.json', 'mcp-servers.json')) {
        $srcFile = Join-Path $ClaudeConfig $f
        if (Test-Path $srcFile) {
            Copy-Item $srcFile (Join-Path $UserClaudeDir $f) -Force
        }
    }

    foreach ($sub in @('subagents', 'skills', 'commands')) {
        $srcDir = Join-Path $ClaudeConfig $sub
        $dstDir = Join-Path $UserClaudeDir $sub
        if (Test-Path $srcDir) {
            if (-not (Test-Path $dstDir)) {
                New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
            }
            $rcExit = Invoke-Native { robocopy $srcDir $dstDir /MIR /NJH /NJS /NDL /NP /NFL /R:1 /W:1 }
            if ($rcExit -ge 8) {
                Write-Err "robocopy $sub failed with code $rcExit"
                exit 1
            }
        }
    }
    Write-Ok 'Claude Code config mirrored'
}

# --- 9. Finale message ------------------------------------------------------
Write-Host ""
Write-Host "=======================================================" -ForegroundColor White
Write-Host "Setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Find Claude in your Start menu (or look for the Claude icon on"
Write-Host "     your desktop) and open it."
Write-Host "  2. Sign in with your Anthropic account."
Write-Host "     - If you don't have one yet, the app will walk you through it."
Write-Host "       Use your @chasegroupcc.com email when prompted."
Write-Host "  3. The first time you ask Claude about your mail, calendar, or"
Write-Host "     SharePoint, it will pop up a Microsoft sign-in. Approve it"
Write-Host "     with your @chasegroupcc.com account."
Write-Host "  4. Try something like:"
Write-Host '       "What is on my calendar today?"' -ForegroundColor DarkGray
Write-Host '       "Find emails from Mitchell Rotolo about FPK this week."' -ForegroundColor DarkGray
Write-Host '       "Show me what is in the 25-116 800 E Farrel folder."' -ForegroundColor DarkGray
Write-Host ""

if ($IncludeClaudeCode) {
    Write-Host "Claude Code (CLI) is also installed for power-user workflows." -ForegroundColor White
    Write-Host "  Open a NEW terminal, type 'claude', sign in, then run '/onboard'." -ForegroundColor DarkGray
    Write-Host "  Use this when you want subagents (PM, Email, Operator)," -ForegroundColor DarkGray
    Write-Host "  slash commands, or multi-step agentic tasks." -ForegroundColor DarkGray
    Write-Host ""
}
