<#
.SYNOPSIS
    Chase Cowork - one-button bootstrap for Chase Group Construction employees.

.DESCRIPTION
    Truly self-contained. Downloads the public bootstrap bundle from
    GitHub, extracts it locally, runs the installer. No SharePoint sync,
    no OneDrive shortcuts, no preconditions other than internet access.

    Resilient by design:
      - Window never closes silently. Always Read-Host pauses at the end.
      - All output (including errors) is logged to Desktop\cowork-install.log.
      - Any unhandled error is caught, printed, and the log path surfaced.

.NOTES
    Distributed via public Gist; pasted by Chase into a Teams chat.
    Source of truth for the bundle: https://github.com/grantdozier/claude-cowork-public
    The script itself contains no secrets - safe to host publicly.
#>

[CmdletBinding()]
param(
    # Pass -IncludeClaudeCode to also install Claude Code (CLI) for power users.
    # Default is Claude Desktop only.
    [switch]$IncludeClaudeCode,

    # Overrides for fork / mirror scenarios.
    [string]$BundleUrl     = 'https://github.com/grantdozier/claude-cowork-public/archive/refs/heads/main.zip',
    [string]$InstallRoot   = (Join-Path $env:LOCALAPPDATA 'chase-cowork\install')
)

# --- Always log everything ---------------------------------------------------
$LogPath = Join-Path $env:USERPROFILE 'Desktop\cowork-install.log'
$transcriptStarted = $false
try {
    Start-Transcript -Path $LogPath -Force -IncludeInvocationHeader | Out-Null
    $transcriptStarted = $true
} catch {
    Write-Host "(transcript could not start: $($_.Exception.Message))" -ForegroundColor DarkYellow
}

# --- Helpers -----------------------------------------------------------------
function Show-Banner ([string]$msg, [string]$color = 'White') {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor $color
    Write-Host " $msg" -ForegroundColor $color
    Write-Host "================================================" -ForegroundColor $color
    Write-Host ""
}

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

# --- Main --------------------------------------------------------------------
try {
    Show-Banner "Chase Cowork - Quick Start"
    Write-Host "Sets up Claude Code on your laptop with the company configuration." -ForegroundColor White
    Write-Host "Takes about 5 minutes. Windows may prompt you to allow installs - say yes." -ForegroundColor DarkGray
    Write-Host ""

    # --- 1. Download the public bootstrap bundle ---------------------------
    Write-Host "Downloading the latest bootstrap bundle..." -ForegroundColor White
    Write-Host "  Source: $BundleUrl" -ForegroundColor DarkGray

    $zipPath = Join-Path $env:TEMP 'chase-cowork-bundle.zip'
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    # Use TLS 1.2 explicitly (older PowerShell defaults are weaker)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    Invoke-WebRequest -Uri $BundleUrl -OutFile $zipPath -UseBasicParsing
    $zipSize = (Get-Item $zipPath).Length
    Write-Host "  [OK] Downloaded $zipSize bytes" -ForegroundColor Green

    # --- 2. Extract -------------------------------------------------------
    Write-Host "Extracting to $InstallRoot..." -ForegroundColor White
    if (Test-Path $InstallRoot) {
        Remove-Item $InstallRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

    Expand-Archive -Path $zipPath -DestinationPath $InstallRoot -Force
    Remove-Item $zipPath -Force

    # GitHub zips wrap content in a folder like claude-cowork-public-main/
    $extractedRoot = Get-ChildItem $InstallRoot -Directory | Select-Object -First 1
    if (-not $extractedRoot) {
        throw "Bundle extracted but no top-level folder found inside $InstallRoot"
    }
    $coworkRoot = $extractedRoot.FullName
    Write-Host "  [OK] Extracted to: $coworkRoot" -ForegroundColor Green

    $setupPath  = Join-Path $coworkRoot 'bootstrap\setup.ps1'
    $verifyPath = Join-Path $coworkRoot 'bootstrap\verify.ps1'

    if (-not (Test-Path $setupPath)) {
        throw "setup.ps1 not found at $setupPath - bundle structure unexpected"
    }

    # --- 3. Run setup.ps1 --------------------------------------------------
    Show-Banner "Installing platform" 'Cyan'
    if ($IncludeClaudeCode) {
        Write-Host "Mode: HYBRID (Claude Desktop + Claude Code CLI)" -ForegroundColor White
        & $setupPath -IncludeClaudeCode
    } else {
        Write-Host "Mode: DESKTOP (Claude Desktop only - default)" -ForegroundColor White
        Write-Host "To also install Claude Code CLI for power-user workflows, rerun with -IncludeClaudeCode." -ForegroundColor DarkGray
        & $setupPath
    }
    $setupExit = $LASTEXITCODE

    if ($setupExit -and $setupExit -ne 0) {
        Show-Banner "Installer reported issues" 'Yellow'
        Write-Host "Scroll up and read the messages. Most of the time, re-running fixes it."
        Pause-And-Exit $setupExit
    }

    # --- 4. Run verify.ps1 -------------------------------------------------
    Show-Banner "Health check" 'Cyan'
    & $verifyPath
    $verifyExit = $LASTEXITCODE

    # --- 5. Next steps -----------------------------------------------------
    if ($verifyExit -eq 0) {
        Show-Banner "Ready to use" 'Green'
        Write-Host "Open Claude Desktop and sign in:" -ForegroundColor White
        Write-Host ""
        Write-Host "  1. Click the " -NoNewline
        Write-Host "Claude" -ForegroundColor Yellow -NoNewline
        Write-Host " icon (Start menu or desktop)."
        Write-Host "  2. Sign in with your Anthropic account."
        Write-Host "     If you don't have one, the app will walk you through it."
        Write-Host "     Use your @chasegroupcc.com email when it prompts."
        Write-Host "  3. The first time you ask Claude about your mail / calendar /"
        Write-Host "     SharePoint, a Microsoft sign-in pops up. Approve it with"
        Write-Host "     your @chasegroupcc.com account."
        Write-Host "  4. Try asking Claude:" -ForegroundColor White
        Write-Host '       "What is on my calendar today?"' -ForegroundColor DarkGray
        Write-Host '       "Find emails from Mitchell Rotolo about FPK this week."' -ForegroundColor DarkGray
        Write-Host '       "Show me what is in the 25-116 800 E Farrel folder."' -ForegroundColor DarkGray
        Write-Host ""
        if ($IncludeClaudeCode) {
            Write-Host "Claude Code CLI is also installed for power-user workflows." -ForegroundColor White
            Write-Host "  Open a NEW terminal, type 'claude', sign in, then '/onboard'." -ForegroundColor DarkGray
            Write-Host ""
        }
        Write-Host "Need help? Message Chase."
        Pause-And-Exit 0
    } else {
        Show-Banner "Some checks failed" 'Yellow'
        Write-Host "Scroll up to see what didn't pass."
        Write-Host "Re-running this quickstart often fixes it."
        Write-Host "If not, send Chase the log file from Desktop\cowork-install.log."
        Pause-And-Exit $verifyExit
    }

} catch {
    Show-Banner "UNEXPECTED ERROR" 'Red'
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Where it happened:" -ForegroundColor DarkGray
    Write-Host "$($_.ScriptStackTrace)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Send Chase the log file:" -ForegroundColor Yellow
    Write-Host "  $LogPath" -ForegroundColor DarkGray
    Pause-And-Exit 1
}
