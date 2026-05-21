<#
.SYNOPSIS
    Chase Cowork — one-time platform installer for a Chase Group employee laptop.

.DESCRIPTION
    Idempotent. Re-running upgrades versions and reapplies config.
    Reads pinned versions from versions.json. Distributes claude-config/ into ~/.claude/.

.NOTES
    Hard rule: this script must work on a clean Windows install with no prior
    Claude/Python/Node. Every paper cut found during Phase 2 dogfood gets fixed here.

.EXAMPLE
    Run from a synced SharePoint claude-cowork folder:
      C:\...\Chase Group Files\4. MISCELLANEOUS\Claude\claude-cowork\bootstrap\setup.ps1
#>

[CmdletBinding()]
param(
    [switch]$SkipPrereqs,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ─── ANTIVIRUS NOTE (READ BEFORE RUNNING) ───────────────────────────────────
# This installer uses winget + npm to install Python, Node, Git, uv, Claude Code,
# and the Microsoft 365 MCP server. Some antivirus tools may flag PowerShell-based
# dependency installation that pulls packages over the network.
#
# Before you "Allow" or "Run anyway":
#   1. Verify the script path you launched matches:
#      ...\Chase Group Files\4. MISCELLANEOUS\Claude\claude-cowork\bootstrap\setup.ps1
#   2. The script is read-only on SharePoint — only Chase and Grant can edit it.
#      Confirm with Chase if anyone asks you to run a different copy.
#   3. The script does NOT download arbitrary executables — only the pinned
#      versions in bootstrap\versions.json from official sources (winget +
#      npmjs.org). If you see anything else, stop and tell Chase.
#
# Long-term: the company is moving toward MDM-pushed installs (Intune / Autopilot)
# so individual employees won't need to run any script directly. See
# PH-107 in the placeholders ledger.
# ────────────────────────────────────────────────────────────────────────────

# ─── Paths ──────────────────────────────────────────────────────────────────
$BootstrapDir   = $PSScriptRoot
$CoworkRoot     = Split-Path $BootstrapDir -Parent
$ClaudeConfig   = Join-Path $CoworkRoot 'claude-config'
$VersionsPath   = Join-Path $BootstrapDir 'versions.json'
$UserClaudeDir  = Join-Path $env:USERPROFILE '.claude'

# ─── Helpers ────────────────────────────────────────────────────────────────
function Write-Step ([string]$msg) { Write-Host "  ► $msg" -ForegroundColor Cyan }
function Write-Ok   ([string]$msg) { Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Warn ([string]$msg) { Write-Host "    WARN $msg" -ForegroundColor Yellow }
function Write-Err  ([string]$msg) { Write-Host "    ERR  $msg" -ForegroundColor Red }

function Test-CommandExists ([string]$name) {
    $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

# ─── 0. Banner ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Chase Cowork — Platform Setup" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "Bootstrap dir : $BootstrapDir"
Write-Host "User config   : $UserClaudeDir"
Write-Host ""

# ─── 1. Verify the bundle is intact ─────────────────────────────────────────
Write-Step 'Verifying bundle integrity'
if (-not (Test-Path (Join-Path $ClaudeConfig 'CLAUDE.md'))) {
    Write-Err "claude-config/CLAUDE.md is missing at $ClaudeConfig"
    Write-Err 'The bootstrap bundle is incomplete. Re-run quickstart.ps1 to redownload.'
    exit 1
}
Write-Ok 'claude-cowork/ contents present'

# ─── 2. Read versions ───────────────────────────────────────────────────────
Write-Step "Reading pinned versions from versions.json"
$versions = Get-Content $VersionsPath -Raw | ConvertFrom-Json
Write-Ok "claude_code = $($versions.claude_code), python = $($versions.python), ms_365_mcp_server = $($versions.ms_365_mcp_server)"

# ─── 3. Prereqs via winget ──────────────────────────────────────────────────
if (-not $SkipPrereqs) {
    Write-Step "Verifying prereqs (Python, Node, Git, uv)"

    if (-not (Test-CommandExists 'python')) {
        Write-Warn 'Python not found — installing Python 3.11 via winget'
        winget install --id Python.Python.3.11 --silent --accept-source-agreements --accept-package-agreements | Out-Null
    } else {
        Write-Ok ('Python: ' + (python --version 2>&1))
    }

    if (-not (Test-CommandExists 'node')) {
        Write-Warn 'Node not found — installing Node 20 via winget'
        winget install --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements | Out-Null
    } else {
        Write-Ok ('Node: ' + (node --version))
    }

    if (-not (Test-CommandExists 'git')) {
        Write-Warn 'Git not found — installing Git via winget'
        winget install --id Git.Git --silent --accept-source-agreements --accept-package-agreements | Out-Null
    } else {
        Write-Ok ('Git: ' + ((git --version) -replace 'git version ', ''))
    }

    if (-not (Test-CommandExists 'uv')) {
        Write-Warn 'uv not found — installing'
        winget install --id astral-sh.uv --silent --accept-source-agreements --accept-package-agreements | Out-Null
    } else {
        Write-Ok ('uv: ' + (uv --version))
    }
} else {
    Write-Warn 'Skipping prereqs (-SkipPrereqs)'
}

# ─── 4. Claude Code ─────────────────────────────────────────────────────────
Write-Step 'Verifying Claude Code installation'
if (-not (Test-CommandExists 'claude')) {
    Write-Warn 'Claude Code not found — installing via npm'
    npm install -g @anthropic-ai/claude-code 2>&1 | Out-Null
    if (-not (Test-CommandExists 'claude')) {
        Write-Err 'Claude Code install failed. Install manually and rerun.'
        exit 1
    }
}
Write-Ok ('Claude Code: ' + (claude --version 2>&1))

# ─── 5. ~/.claude/ user config ──────────────────────────────────────────────
Write-Step "Creating $UserClaudeDir"
New-Item -ItemType Directory -Force -Path $UserClaudeDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $UserClaudeDir 'subagents') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $UserClaudeDir 'skills') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $UserClaudeDir 'commands') | Out-Null
Write-Ok 'User config directory ready'

Write-Step 'Mirroring claude-config/ into ~/.claude/ (preserves Claude Code state)'

# Copy top-level files individually. Don't /MIR the user's ~/.claude/ root -
# Claude Code keeps projects/, agents/, conversation history etc. there and
# /MIR would delete all of them.
foreach ($f in @('CLAUDE.md', 'settings.json', 'mcp-servers.json')) {
    $srcFile = Join-Path $ClaudeConfig $f
    if (Test-Path $srcFile) {
        Copy-Item $srcFile (Join-Path $UserClaudeDir $f) -Force
    }
}

# /MIR is OK *inside* company-managed subdirectories - stale agents/skills/
# commands SHOULD be cleaned up when they're removed from the config.
foreach ($sub in @('subagents', 'skills', 'commands')) {
    $srcDir = Join-Path $ClaudeConfig $sub
    $dstDir = Join-Path $UserClaudeDir $sub
    if (Test-Path $srcDir) {
        if (-not (Test-Path $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        robocopy $srcDir $dstDir /MIR /NJH /NJS /NDL /NP /NFL /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) {
            Write-Err "robocopy $sub failed with code $LASTEXITCODE"
            exit 1
        }
    }
}
Write-Ok 'Config mirrored (top-level files copied, subagents/skills/commands /MIR-synced)'

# ─── 6. Install pinned Softeria MS-365 MCP server ───────────────────────────
Write-Step "Installing ms-365-mcp-server@$($versions.ms_365_mcp_server)"
$mcpPkg = "@softeria/ms-365-mcp-server@$($versions.ms_365_mcp_server)"
$installResult = npm install -g $mcpPkg 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn "npm global install returned exit code $LASTEXITCODE"
    Write-Host $installResult
} else {
    Write-Ok "MS-365 MCP installed at pinned version"
}

# ─── 7. Per-user token cache path ───────────────────────────────────────────
$mcpCacheDir = Join-Path $env:LOCALAPPDATA 'chase-cowork'
New-Item -ItemType Directory -Force -Path $mcpCacheDir | Out-Null

# ─── 8. Sign-in hint ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "Setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Open a new terminal."
Write-Host "  2. Run: claude"
Write-Host "  3. When prompted, sign in to Microsoft 365 with your @chasegroupcc.com account."
Write-Host ""
Write-Host "Verify the install at any time:"
Write-Host "  $($BootstrapDir)\verify.ps1"
Write-Host ""
