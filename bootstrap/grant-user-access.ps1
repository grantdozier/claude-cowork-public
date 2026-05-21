<#
.SYNOPSIS
    Admin script: grant a new user access to the Chase Cowork corpus (Phase 5).

.DESCRIPTION
    Run this ONCE per new user, from the admin machine (Chase's laptop).
    Automates the four per-user Azure grants from docs/DEPLOYMENT_RUNBOOK.md §3:
      1. Key Vault access POLICY (get + list) on kv-chase-cowork-5f74
         NOTE: This vault uses Access Policy mode, NOT RBAC. RBAC roles are inert.
      2. SQL db_datareader on chasecowork-audit
      3. Deploys users.toml to the target machine's %LOCALAPPDATA% path
         (requires the target machine to have a mapped path or UNC share set via -TargetProfile)

    Prerequisites (run once per environment, not per user):
      - az sql server ad-admin must be set on sql-chase-cowork-5f74 (see §3a).
        If it returns empty run:
          az sql server ad-admin create --resource-group rg-chase-cowork-prod `
            --server sql-chase-cowork-5f74 --display-name chase `
            --object-id (az ad signed-in-user show --query id -o tsv)
      - App admin consent granted org-wide for App #1 e2b1eeec-... (see §5).

.PARAMETER User
    The @chasegroupcc.com SMTP address of the user being onboarded.
    Example: shawnee@chasegroupcc.com

.PARAMETER TargetProfile
    Path to the user's local AppData\Local on THEIR machine.
    Use a UNC path if you have remote access: \\DESKTOP-DONNA\c$\Users\ChelseaCouvillion\AppData\Local
    If omitted, only Azure grants are done; you must deploy users.toml manually.

.PARAMETER UsersTomlSource
    Path to the canonical users.toml. Defaults to the copy in this repo.

.EXAMPLE
    # Grant Azure access + copy users.toml to Shawnee's machine remotely:
    .\grant-user-access.ps1 -User shawnee@chasegroupcc.com `
        -TargetProfile "\\DESKTOP-DONNA\c$\Users\ChelseaCouvillion\AppData\Local"

    # Grant Azure access only (then manually copy users.toml):
    .\grant-user-access.ps1 -User shawnee@chasegroupcc.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$User,

    [string]$TargetProfile = "",

    [string]$UsersTomlSource = ""
)

$ErrorActionPreference = 'Stop'

# Resolve users.toml source
if (-not $UsersTomlSource) {
    $scriptDir = Split-Path $PSScriptRoot -Parent
    $UsersTomlSource = Join-Path $scriptDir "claude-cowork-audit\config\users.toml"
    if (-not (Test-Path $UsersTomlSource)) {
        # Try repo root
        $repoRoot = Split-Path $scriptDir -Parent
        $UsersTomlSource = Join-Path $repoRoot "claude-cowork-audit\config\users.toml"
    }
}

Write-Host ""
Write-Host "Chase Cowork - Grant User Access" -ForegroundColor White
Write-Host "=================================" -ForegroundColor White
Write-Host "User:            $User" -ForegroundColor DarkGray
Write-Host "TargetProfile:   $(if ($TargetProfile) { $TargetProfile } else { '(skipped - do manually)' })" -ForegroundColor DarkGray
Write-Host "users.toml from: $UsersTomlSource" -ForegroundColor DarkGray
Write-Host ""

# Step 1 — Key Vault access POLICY
Write-Host "[1/3] Granting Key Vault access POLICY (get + list) for $User..." -ForegroundColor Cyan
Write-Host "      NOTE: This vault uses Access Policy mode. RBAC roles do NOT apply." -ForegroundColor Yellow
try {
    $kvResult = az keyvault set-policy `
        --name kv-chase-cowork-5f74 `
        --upn $User `
        --secret-permissions get list `
        2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "      ERR  az keyvault set-policy failed: $kvResult" -ForegroundColor Red
        Write-Host "           Make sure you are logged in as subscription owner: az login" -ForegroundColor Yellow
    } else {
        Write-Host "      OK   Key Vault access policy set for $User" -ForegroundColor Green
    }
} catch {
    Write-Host "      ERR  $_" -ForegroundColor Red
    Write-Host "           Is az CLI installed and logged in? Run: az login" -ForegroundColor Yellow
}

# Step 2 — SQL db_datareader
Write-Host ""
Write-Host "[2/3] Granting SQL db_datareader on chasecowork-audit for $User..." -ForegroundColor Cyan
Write-Host "      This requires sqlcmd on PATH and the SQL server to have an Entra admin set." -ForegroundColor DarkGray

$sqlcmdAvailable = $null -ne (Get-Command sqlcmd -ErrorAction SilentlyContinue)
if (-not $sqlcmdAvailable) {
    Write-Host "      SKIP sqlcmd not on PATH -- run manually:" -ForegroundColor Yellow
    Write-Host "        sqlcmd -S sql-chase-cowork-5f74.database.windows.net -d chasecowork-audit -G" -ForegroundColor DarkGray
    Write-Host "        > CREATE USER [$User] FROM EXTERNAL PROVIDER;" -ForegroundColor DarkGray
    Write-Host "        > ALTER ROLE db_datareader ADD MEMBER [$User];" -ForegroundColor DarkGray
    Write-Host "        > GO" -ForegroundColor DarkGray
} else {
    # First check / create the user, then add role (two separate commands for sqlcmd compatibility)
    $createUserSql = "IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$User') BEGIN CREATE USER [$User] FROM EXTERNAL PROVIDER END"
    $addRoleSql    = "ALTER ROLE db_datareader ADD MEMBER [$User]"

    $sqlExit1 = sqlcmd -S "sql-chase-cowork-5f74.database.windows.net" -d "chasecowork-audit" -G -Q $createUserSql 2>&1
    $sqlExit2 = sqlcmd -S "sql-chase-cowork-5f74.database.windows.net" -d "chasecowork-audit" -G -Q $addRoleSql 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "      OK   db_datareader granted for $User" -ForegroundColor Green
    } else {
        Write-Host "      WARN sqlcmd output: $sqlExit1 / $sqlExit2" -ForegroundColor Yellow
        Write-Host "           Verify manually or check SQL Entra admin setting (see §3a of DEPLOYMENT_RUNBOOK.md)" -ForegroundColor Yellow
    }
}

# Step 3 — Deploy users.toml
Write-Host ""
Write-Host "[3/3] Deploying users.toml..." -ForegroundColor Cyan

if (-not (Test-Path $UsersTomlSource)) {
    Write-Host "      ERR  users.toml not found at: $UsersTomlSource" -ForegroundColor Red
    Write-Host "           Locate the canonical users.toml in the private repo and re-run with -UsersTomlSource" -ForegroundColor Yellow
} elseif (-not $TargetProfile) {
    Write-Host "      SKIP -TargetProfile not set. Deploy manually:" -ForegroundColor Yellow
    Write-Host "        On $($User.Split('@')[0])'s machine, run (as admin or user):" -ForegroundColor DarkGray
    Write-Host '        New-Item -ItemType Directory -Force -Path "$env:LOCALAPPDATA\claude-cowork-audit\config"' -ForegroundColor DarkGray
    Write-Host "        Copy the canonical users.toml to:" -ForegroundColor DarkGray
    Write-Host '        %LOCALAPPDATA%\claude-cowork-audit\config\users.toml' -ForegroundColor DarkGray
    Write-Host "        (Save as UTF-8 without BOM)" -ForegroundColor DarkGray
} else {
    $destDir  = Join-Path $TargetProfile 'claude-cowork-audit\config'
    $destPath = Join-Path $destDir 'users.toml'
    try {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        # Write as UTF-8 without BOM
        $content = Get-Content $UsersTomlSource -Raw
        [System.IO.File]::WriteAllText($destPath, $content, (New-Object System.Text.UTF8Encoding $false))
        Write-Host "      OK   users.toml deployed to $destPath" -ForegroundColor Green
    } catch {
        Write-Host "      ERR  Could not copy to $destPath : $_" -ForegroundColor Red
        Write-Host "           Try opening a remote session or using a UNC path." -ForegroundColor Yellow
    }
}

# Summary
Write-Host ""
Write-Host "=====================================================" -ForegroundColor White
Write-Host " Per-user grants for $User" -ForegroundColor White
Write-Host "=====================================================" -ForegroundColor White
Write-Host ""
Write-Host "Remaining steps for the USER to do on THEIR machine:" -ForegroundColor White
Write-Host "  1. az login   (sign in as $User, NOT the admin alt)" -ForegroundColor DarkGray
Write-Host "  2. Restart Claude Desktop" -ForegroundColor DarkGray
Write-Host "  3. Ask Claude: 'whoami' to confirm corpus access" -ForegroundColor DarkGray
Write-Host ""
Write-Host "If 'whoami' still returns 'anonymous':" -ForegroundColor White
Write-Host "  - Confirm users.toml exists at %LOCALAPPDATA%\claude-cowork-audit\config\users.toml" -ForegroundColor DarkGray
Write-Host "  - Confirm CHASE_INTERNAL_USER env var is set in claude_desktop_config.json" -ForegroundColor DarkGray
Write-Host "  - See docs/DEPLOYMENT_RUNBOOK.md §4 for the full diagnostic." -ForegroundColor DarkGray
Write-Host ""
