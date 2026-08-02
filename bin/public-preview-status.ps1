param(
  [string]$StatusPath = ""
)

$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
$path = if ($StatusPath) {
  [System.IO.Path]::GetFullPath($StatusPath)
} else {
  Join-Path $repository "tmp\public-preview.json"
}

if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
  throw "Preview status not found: $path"
}

$status = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
$listener = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue |
  Select-Object -First 1
$railsPid = if ($listener) { $listener.OwningProcess } else { $status.rails_pid }
$rails = Get-Process -Id $railsPid -ErrorAction SilentlyContinue
$tunnel = Get-Process -Id $status.tunnel_pid -ErrorAction SilentlyContinue
$database = Get-Item -LiteralPath $status.database -ErrorAction SilentlyContinue

$areas = @("sz", "sh", "bj")
$localStatuses = [ordered]@{}
$publicStatuses = [ordered]@{}
foreach ($area in $areas) {
  $localStatuses[$area] = try {
    (Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:3000/$area" -TimeoutSec 15).StatusCode
  } catch {
    0
  }
  $publicStatuses[$area] = try {
    (Invoke-WebRequest -UseBasicParsing -Uri "$($status.url)/$area" -TimeoutSec 15).StatusCode
  } catch {
    0
  }
}
$marketsHealthy = @($areas | Where-Object { $localStatuses[$_] -ne 200 -or $publicStatuses[$_] -ne 200 }).Count -eq 0

$report = [pscustomobject]@{
  Url = $status.url
  StartedAt = $status.started_at
  RailsPid = $railsPid
  RecordedRailsPid = $status.rails_pid
  RailsRunning = $rails -and $rails.ProcessName -eq "ruby"
  TunnelPid = $status.tunnel_pid
  TunnelRunning = $tunnel -and $tunnel.ProcessName -eq "cloudflared"
  LocalMarkets = ($areas | ForEach-Object { "$_=$($localStatuses[$_])" }) -join ", "
  PublicMarkets = ($areas | ForEach-Object { "$_=$($publicStatuses[$_])" }) -join ", "
  DatabaseBytes = $database.Length
  Healthy = $rails -and $tunnel -and $marketsHealthy
}
$report
if (-not $report.Healthy) { exit 1 }
