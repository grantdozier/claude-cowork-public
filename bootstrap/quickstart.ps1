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
    # Override these if you ever fork the public mirror.
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
    & $setupPath
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
        Write-Host "Three things to do next:" -ForegroundColor White
        Write-Host ""
        Write-Host "  1. Close this PowerShell window."
        Write-Host "  2. Open a NEW PowerShell or Terminal window."
        Write-Host "     (Important - it needs to be new so it picks up the new programs.)"
        Write-Host "  3. Type: " -NoNewline
        Write-Host "claude" -ForegroundColor Yellow
        Write-Host "     Sign in with your @chasegroupcc.com account when asked."
        Write-Host "  4. Once Claude is running, type: " -NoNewline
        Write-Host "/onboard" -ForegroundColor Yellow
        Write-Host "     This runs a first-time health check (M365 sign-in, mailbox,"
        Write-Host "     calendar, SharePoint, personal folder) and tells you if"
        Write-Host "     anything needs Chase's attention."
        Write-Host ""
        Write-Host "After that, try asking Claude things like:" -ForegroundColor White
        Write-Host '  "What''s on my calendar today?"'
        Write-Host '  "Find emails from Mitchell Rotolo about FPK this week."'
        Write-Host '  "Show me what''s in the 25-116 800 E Farrel folder."'
        Write-Host ""
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
