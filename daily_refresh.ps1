#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

$env:PATH = "C:\Ruby34-x64\bin;" + $env:PATH
$env:TDX_DATA_PATH = "C:\new_tdx\vipdoc"
Set-Location "C:\Users\huntl\work\stave"

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting daily refresh..." -ForegroundColor Cyan

try {
    bundle exec rails daily_refresh
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Daily refresh completed successfully." -ForegroundColor Green
} catch {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR: $_" -ForegroundColor Red
    exit 1
}
