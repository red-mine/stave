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
$startedAt = try {
  if ($status.started_at -is [DateTime]) {
    $status.started_at.ToLocalTime()
  } else {
    [DateTimeOffset]::Parse($status.started_at).ToLocalTime()
  }
} catch {
  $status.started_at
}
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

$areas = @("sz", "sh", "bj")
function Get-ApplicationHealth([string]$Uri) {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 15
    $body = $response.Content | ConvertFrom-Json
    $details = foreach ($area in $areas) {
      $market = $body.markets.PSObject.Properties[$area].Value
      "$area=$($market.date)/$($market.rows)/$($market.snapshot_rows)"
    }
    $marketsReady = @($areas | Where-Object {
      $market = $body.markets.PSObject.Properties[$_].Value
      -not $market -or -not $market.ready -or -not $market.date -or [int]$market.rows -le 0 -or
        $market.snapshot_date -ne $market.date -or [int]$market.snapshot_rows -ne [int]$market.rows
    }).Count -eq 0
    return [pscustomobject]@{
      Code = $response.StatusCode
      Ready = $response.StatusCode -eq 200 -and $body.status -eq "ready" -and $body.environment -eq "development" -and $body.log_level -eq "warn" -and $body.dates_aligned -and $marketsReady
      Markets = $details -join ", "
    }
  } catch {
    return [pscustomobject]@{ Code = 0; Ready = $false; Markets = "unavailable" }
  }
}

$localApplication = Get-ApplicationHealth "http://127.0.0.1:$port/preview-health"
$publicApplication = Get-ApplicationHealth "$($status.url)/preview-health"
$localStatuses = [ordered]@{}
$publicStatuses = [ordered]@{}
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
}
$marketsHealthy = @($areas | Where-Object {
  $localStatuses[$_] -ne 200 -or $publicStatuses[$_] -ne 200
}).Count -eq 0

$report = [pscustomobject]@{
  Url = $status.url
  StartedAt = $startedAt
  Environment = if ($status.environment) { $status.environment } else { "unknown" }
  LogLevel = if ($status.log_level) { $status.log_level } else { "unknown" }
  ServerEnvironment = $serverEnvironment
  Port = $port
  RailsPid = $railsPid
  RecordedRailsPid = $status.rails_pid
  RailsRunning = $rails -and $rails.ProcessName -eq "ruby"
  TunnelPid = $status.tunnel_pid
  TunnelRunning = $tunnel -and $tunnel.ProcessName -eq "cloudflared"
  LocalMarkets = ($areas | ForEach-Object { "$_=$($localStatuses[$_])" }) -join ", "
  PublicMarkets = ($areas | ForEach-Object { "$_=$($publicStatuses[$_])" }) -join ", "
  LocalApplication = "$($localApplication.Code)/$(if ($localApplication.Ready) { 'ready' } else { 'incomplete' }) [$($localApplication.Markets)]"
  PublicApplication = "$($publicApplication.Code)/$(if ($publicApplication.Ready) { 'ready' } else { 'incomplete' }) [$($publicApplication.Markets)]"
  IsolatedDatabase = $databaseIsIsolated
  DatabaseBytes = $database.Length
  Healthy = $rails -and $tunnel -and $marketsHealthy -and $localApplication.Ready -and $publicApplication.Ready -and $databaseIsIsolated -and $status.environment -eq "development" -and $serverEnvironment -eq "development" -and $status.log_level -eq "warn"
}
$report
if (-not $report.Healthy -and -not $ReturnOnly) { exit 1 }
