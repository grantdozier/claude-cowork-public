<#
.SYNOPSIS
    Chase Cowork — health check / install verifier.
    Produces a PASS/FAIL/WARN report.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$results = @()

function Add-Result ([string]$name, [string]$status, [string]$detail) {
    $script:results += [PSCustomObject]@{
        Check  = $name
        Status = $status
        Detail = $detail
    }
}

function Test-CommandExists ([string]$name) {
    $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

$BootstrapDir = $PSScriptRoot
$CoworkRoot   = Split-Path $BootstrapDir -Parent
$ClaudeConfig = Join-Path $CoworkRoot 'claude-config'
$UserClaudeDir = Join-Path $env:USERPROFILE '.claude'
$VersionsPath = Join-Path $BootstrapDir 'versions.json'
$versions = Get-Content $VersionsPath -Raw | ConvertFrom-Json

# OneDrive sync
if (Test-Path (Join-Path $ClaudeConfig 'CLAUDE.md')) {
    Add-Result 'OneDrive sync' 'PASS' 'claude-config/CLAUDE.md present'
} else {
    Add-Result 'OneDrive sync' 'FAIL' 'claude-config/ contents missing'
}

# Python
if (Test-CommandExists 'python') {
    $py = (python --version 2>&1)
    Add-Result 'Python' 'PASS' $py
} else {
    Add-Result 'Python' 'FAIL' "missing — pinned $($versions.python)"
}

# Node
if (Test-CommandExists 'node') {
    Add-Result 'Node' 'PASS' (node --version)
} else {
    Add-Result 'Node' 'FAIL' "missing — pinned $($versions.node)"
}

# Git
if (Test-CommandExists 'git') {
    Add-Result 'Git' 'PASS' ((git --version) -replace 'git version ', '')
} else {
    Add-Result 'Git' 'FAIL' 'missing'
}

# uv
if (Test-CommandExists 'uv') {
    Add-Result 'uv' 'PASS' (uv --version)
} else {
    Add-Result 'uv' 'WARN' 'missing — optional for now'
}

# Claude Code
if (Test-CommandExists 'claude') {
    Add-Result 'Claude Code' 'PASS' ((claude --version 2>&1) | Select-Object -First 1)
} else {
    Add-Result 'Claude Code' 'FAIL' 'not installed — run setup.ps1'
}

# User config mirrored
if (Test-Path (Join-Path $UserClaudeDir 'CLAUDE.md')) {
    Add-Result '~/.claude/ mirror' 'PASS' 'CLAUDE.md present'
} else {
    Add-Result '~/.claude/ mirror' 'FAIL' 'not mirrored — run setup.ps1'
}

# MS-365 MCP
$mcpCheck = npm list -g "@softeria/ms-365-mcp-server" --depth=0 2>&1 | Out-String
if ($mcpCheck -match "ms-365-mcp-server@($($versions.ms_365_mcp_server)|\d)") {
    Add-Result 'MS-365 MCP' 'PASS' ($mcpCheck -split "`n" | Where-Object { $_ -match 'ms-365-mcp-server' } | Select-Object -First 1).Trim()
} else {
    Add-Result 'MS-365 MCP' 'FAIL' "not installed — pinned $($versions.ms_365_mcp_server)"
}

# Token cache dir
$cacheDir = Join-Path $env:LOCALAPPDATA 'chase-cowork'
if (Test-Path $cacheDir) {
    Add-Result 'Token cache dir' 'PASS' $cacheDir
} else {
    Add-Result 'Token cache dir' 'WARN' 'will be created on first MCP run'
}

# Report
Write-Host ""
Write-Host "Chase Cowork - Health Check" -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor White
$results | Format-Table -AutoSize

$fails = ($results | Where-Object Status -eq 'FAIL').Count
$warns = ($results | Where-Object Status -eq 'WARN').Count

if ($fails -gt 0) {
    Write-Host "$fails check(s) FAILED. Re-run bootstrap\setup.ps1 to fix." -ForegroundColor Red
    exit 1
} elseif ($warns -gt 0) {
    Write-Host "$warns warning(s). Platform is usable but not 100%." -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "All checks passed. You're good." -ForegroundColor Green
    exit 0
}
