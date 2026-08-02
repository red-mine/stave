param(
  [string]$StatusPath = "",
  [switch]$ReturnOnly
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
$serverLogPath = Join-Path $repository "tmp\public-preview-server-out.log"
$serverLog = if (Test-Path -LiteralPath $serverLogPath -PathType Leaf) {
  Get-Content -LiteralPath $serverLogPath -Raw -ErrorAction SilentlyContinue
} else {
  ""
}
$serverEnvironment = if ($serverLog -match "(?m)^\*\s+Environment:\s+(\S+)\s*$") { $Matches[1] } else { "unknown" }
$port = if ($status.port) { [int]$status.port } else { 3000 }
$listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
  Select-Object -First 1
$railsPid = if ($listener) { $listener.OwningProcess } else { $status.rails_pid }
$rails = Get-Process -Id $railsPid -ErrorAction SilentlyContinue
$tunnel = Get-Process -Id $status.tunnel_pid -ErrorAction SilentlyContinue
$database = Get-Item -LiteralPath $status.database -ErrorAction SilentlyContinue
$isolatedDatabase = [System.IO.Path]::GetFullPath((Join-Path $repository "tmp\ui-stock.sqlite3"))
$databaseIsIsolated = $database -and $database.FullName -eq $isolatedDatabase

function Test-MarketContent($Response) {
  return $Response -and
    $Response.Content -match 'id="current-signals"' -and
    $Response.Content -match 'class="stock-table"' -and
    $Response.Content -notmatch 'Data date\s*<strong>Unavailable</strong>'
}

$areas = @("sz", "sh", "bj")
$localStatuses = [ordered]@{}
$publicStatuses = [ordered]@{}
$localContent = [ordered]@{}
$publicContent = [ordered]@{}
foreach ($area in $areas) {
  $localResponse = try {
    Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/$area" -TimeoutSec 15
  } catch {
    $null
  }
  $publicResponse = try {
    Invoke-WebRequest -UseBasicParsing -Uri "$($status.url)/$area" -TimeoutSec 15
  } catch {
    $null
  }
  $localStatuses[$area] = if ($localResponse) { $localResponse.StatusCode } else { 0 }
  $publicStatuses[$area] = if ($publicResponse) { $publicResponse.StatusCode } else { 0 }
  $localContent[$area] = Test-MarketContent $localResponse
  $publicContent[$area] = Test-MarketContent $publicResponse
}
$marketsHealthy = @($areas | Where-Object {
  $localStatuses[$_] -ne 200 -or $publicStatuses[$_] -ne 200 -or
    -not $localContent[$_] -or -not $publicContent[$_]
}).Count -eq 0

$report = [pscustomobject]@{
  Url = $status.url
  StartedAt = $status.started_at
  Environment = if ($status.environment) { $status.environment } else { "unknown" }
  ServerEnvironment = $serverEnvironment
  Port = $port
  RailsPid = $railsPid
  RecordedRailsPid = $status.rails_pid
  RailsRunning = $rails -and $rails.ProcessName -eq "ruby"
  TunnelPid = $status.tunnel_pid
  TunnelRunning = $tunnel -and $tunnel.ProcessName -eq "cloudflared"
  LocalMarkets = ($areas | ForEach-Object { "$_=$($localStatuses[$_])" }) -join ", "
  PublicMarkets = ($areas | ForEach-Object { "$_=$($publicStatuses[$_])" }) -join ", "
  LocalContent = ($areas | ForEach-Object { "$_=$(if ($localContent[$_]) { 'ready' } else { 'empty' })" }) -join ", "
  PublicContent = ($areas | ForEach-Object { "$_=$(if ($publicContent[$_]) { 'ready' } else { 'empty' })" }) -join ", "
  IsolatedDatabase = $databaseIsIsolated
  DatabaseBytes = $database.Length
  Healthy = $rails -and $tunnel -and $marketsHealthy -and $databaseIsIsolated -and $status.environment -eq "development" -and $serverEnvironment -eq "development"
}
$report
if (-not $report.Healthy -and -not $ReturnOnly) { exit 1 }
