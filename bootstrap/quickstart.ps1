<#
.SYNOPSIS
    Chase Cowork - one-button bootstrap for Chase Group Construction employees.

.DESCRIPTION
    Resilient by design:
      - Window never closes silently. Always Read-Host pauses at the end.
      - All output (including errors) is logged to Desktop\cowork-install.log
        so even if something exotic happens, we have a forensic record.
      - Any unhandled error is caught, printed, and the user is told where
        the log is.

    Locates the SharePoint-synced claude-cowork/ folder using a tiered
    search (known paths first, then recursive scan of OneDrive / Chase
    profile folders for an Add-shortcut-to-OneDrive style install).
    Runs setup.ps1 + verify.ps1.

.NOTES
    Distributed via public GitHub Gist; pasted by Chase into a Teams chat.
    The script itself contains no secrets - safe to host publicly.
#>

[CmdletBinding()]
param()

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
    Write-Host "Takes about 5 minutes. You can keep working on other stuff while it runs."
    Write-Host ""
    Write-Host "Heads-up: Windows may prompt you to allow installs - say yes." -ForegroundColor DarkGray
    Write-Host ""

    # --- 1. Find the SharePoint-synced cowork folder -----------------------
    Write-Host "Looking for the claude-cowork folder on this laptop..." -ForegroundColor White

    $knownPaths = @(
        "$env:USERPROFILE\Chase Construction Group\Chase Group Construction - Documents\Chase Group Files\4. MISCELLANEOUS\Claude\claude-cowork",
        "$env:OneDriveCommercial\Chase Group Construction - Documents\Chase Group Files\4. MISCELLANEOUS\Claude\claude-cowork",
        "$env:USERPROFILE\OneDrive - Chase Construction Group\Chase Group Files\4. MISCELLANEOUS\Claude\claude-cowork",
        "$env:USERPROFILE\OneDrive - Chase Construction Group\Chase Group Construction - Documents\Chase Group Files\4. MISCELLANEOUS\Claude\claude-cowork",
        "$env:USERPROFILE\OneDrive - Chase Construction Group\4. MISCELLANEOUS\Claude\claude-cowork",
        "$env:USERPROFILE\OneDrive - Chase Construction Group\Claude\claude-cowork"
    )

    $coworkRoot = $null
    foreach ($p in $knownPaths) {
        if (Test-Path (Join-Path $p 'bootstrap\setup.ps1')) {
            $coworkRoot = $p
            break
        }
    }

    # Fallback: recursive scan of OneDrive/Chase folders in the user profile
    if (-not $coworkRoot) {
        Write-Host "  Not in any known path. Scanning OneDrive folders (about 20 seconds)..." -ForegroundColor DarkGray
        $searchRoots = Get-ChildItem $env:USERPROFILE -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*OneDrive*' -or $_.Name -like '*Chase*' }
        foreach ($root in $searchRoots) {
            $found = Get-ChildItem $root.FullName -Recurse -Directory -Filter 'claude-cowork' -Depth 8 -ErrorAction SilentlyContinue |
                Where-Object { Test-Path (Join-Path $_.FullName 'bootstrap\setup.ps1') } |
                Select-Object -First 1
            if ($found) { $coworkRoot = $found.FullName; break }
        }
    }

    if (-not $coworkRoot) {
        Show-Banner "Cannot find the company Claude folder" 'Yellow'
        Write-Host "SharePoint isn't syncing the claude-cowork/ folder to this laptop yet."
        Write-Host ""
        Write-Host "Fix it in 2 minutes:" -ForegroundColor White
        Write-Host "  1. Open your browser and sign in to:"
        Write-Host "     https://chasegroupcc.sharepoint.com" -ForegroundColor Cyan
        Write-Host "  2. Go to: Chase Group Files > 4. MISCELLANEOUS > Claude > claude-cowork"
        Write-Host "  3. Click the 'Sync' button at the top of the page."
        Write-Host "  4. Wait until OneDrive shows a green check (about 30 seconds)."
        Write-Host "  5. Re-run this quickstart command."
        Write-Host ""
        Write-Host "If 'Sync' is disabled with the message:" -ForegroundColor White
        Write-Host "  'You are already syncing a shortcut to a folder from this shared library'"
        Write-Host "then you already have a OneDrive shortcut for this library at a higher level."
        Write-Host "Open File Explorer, navigate into your 'OneDrive - Chase Construction Group'"
        Write-Host "folder, find the Claude subfolder (or wherever the shortcut lives), and OPEN it."
        Write-Host "Just clicking into the folder forces OneDrive to download it. Then re-run."
        Write-Host ""
        Write-Host "Paths I checked (none had bootstrap\setup.ps1):" -ForegroundColor DarkGray
        foreach ($p in $knownPaths) { Write-Host "  $p" -ForegroundColor DarkGray }
        Write-Host ""
        Write-Host "If you don't see the Claude folder anywhere, ask Chase for access."
        Pause-And-Exit 1
    }

    Write-Host "[OK] Found claude-cowork at:" -ForegroundColor Green
    Write-Host "  $coworkRoot" -ForegroundColor DarkGray
    Write-Host ""

    $setupPath  = Join-Path $coworkRoot 'bootstrap\setup.ps1'
    $verifyPath = Join-Path $coworkRoot 'bootstrap\verify.ps1'

    # --- 2. Run setup.ps1 --------------------------------------------------
    Show-Banner "Installing platform" 'Cyan'
    & $setupPath
    $setupExit = $LASTEXITCODE

    if ($setupExit -and $setupExit -ne 0) {
        Show-Banner "Installer reported issues" 'Yellow'
        Write-Host "Scroll up and read the messages. Most of the time, re-running fixes it."
        Pause-And-Exit $setupExit
    }

    # --- 3. Run verify.ps1 -------------------------------------------------
    Show-Banner "Health check" 'Cyan'
    & $verifyPath
    $verifyExit = $LASTEXITCODE

    # --- 4. Next steps -----------------------------------------------------
    if ($verifyExit -eq 0) {
        Show-Banner "Ready to use" 'Green'
        Write-Host "Three things to do next:" -ForegroundColor White
        Write-Host ""
        Write-Host "  1. Close this PowerShell window."
        Write-Host "  2. Open a NEW PowerShell or Terminal window."
        Write-Host "     (Important - it needs to be new so it picks up the new programs.)"
        Write-Host "  3. Type: " -NoNewline
        Write-Host "claude" -ForegroundColor Yellow
        Write-Host "     Then sign in with your @chasegroupcc.com account when asked."
        Write-Host ""
        Write-Host "Try asking Claude things like:" -ForegroundColor White
        Write-Host '  "What''s on my calendar today?"'
        Write-Host '  "Find emails from Mitchell Rotolo about FPK this week."'
        Write-Host '  "Show me what''s in the 25-116 800 E Farrel folder."'
        Write-Host ""
        Write-Host "Need help? Message Chase. Full docs:"
        Write-Host "  $coworkRoot\docs\ONBOARDING.md" -ForegroundColor DarkGray
        Write-Host "  $coworkRoot\docs\TROUBLESHOOTING.md" -ForegroundColor DarkGray
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
