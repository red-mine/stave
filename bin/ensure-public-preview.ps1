param(
  [int]$RetryDelaySeconds = 15,
  [int]$MaximumLogBytes = 1MB,
  [int]$RetainedLogLines = 1000
)

$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
$statusScript = Join-Path $PSScriptRoot "public-preview-status.ps1"
$startScript = Join-Path $PSScriptRoot "start-public-preview.ps1"
$statusPath = Join-Path $repository "tmp\public-preview.json"
$logDirectory = Join-Path $repository "log\public-preview"
$logFile = Join-Path $logDirectory "monitor.log"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

function Limit-MonitorLog {
  if (-not (Test-Path -LiteralPath $logFile)) {
    return
  }

  $log = Get-Item -LiteralPath $logFile
  if ($log.Length -le $MaximumLogBytes) {
    return
  }

  $recentLines = Get-Content -LiteralPath $logFile -Tail ([Math]::Max($RetainedLogLines, 1))
  Set-Content -LiteralPath $logFile -Value $recentLines -Encoding utf8
}

Limit-MonitorLog

function Write-MonitorLog([string]$Message) {
  "[$(Get-Date -Format o)] $Message" | Tee-Object -FilePath $logFile -Append
}

function Test-PreviewHealth {
  try {
    $check = & $statusScript -ReturnOnly
    if (-not $check.Healthy) {
      Write-MonitorLog "Health details: rails=$($check.RailsRunning), tunnel=$($check.TunnelRunning), local=[$($check.LocalMarkets)], public=[$($check.PublicMarkets)]."
    }
    return [bool]$check.Healthy
  } catch {
    Write-MonitorLog "Health check could not run: $($_.Exception.Message)"
    return $false
  }
}

if (Test-PreviewHealth) {
  Write-MonitorLog "Preview healthy; no action needed."
  exit 0
}

Write-MonitorLog "Preview health check failed; retrying in $RetryDelaySeconds seconds."
Start-Sleep -Seconds ([Math]::Max($RetryDelaySeconds, 1))
if (Test-PreviewHealth) {
  Write-MonitorLog "Preview recovered on retry; no restart needed."
  exit 0
}

Write-MonitorLog "Preview failed twice; starting verified recovery."
try {
  $previewPort = 3000
  if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
    $savedStatus = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    if ($savedStatus.port) { $previewPort = [int]$savedStatus.port }
  }
  & $startScript -Port $previewPort | Tee-Object -FilePath $logFile -Append
  if (-not (Test-PreviewHealth)) {
    throw "Recovered preview did not pass its health check"
  }
} catch {
  Write-MonitorLog "Preview recovery failed: $($_.Exception.Message)"
  exit 1
}
Write-MonitorLog "Preview recovery succeeded."
