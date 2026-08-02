param(
  [string]$RubyPath = "C:\Ruby34-x64\bin\ruby.exe",
  [string]$DatabasePath = "",
  [int]$Port = 3000
)

$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
$database = if ($DatabasePath) {
  [System.IO.Path]::GetFullPath($DatabasePath)
} else {
  Join-Path $repository "tmp\ui-stock.sqlite3"
}
$cloudflared = Join-Path $repository "tmp\cloudflared\cloudflared.exe"
$tunnelOut = Join-Path $repository "tmp\cloudflared-out.log"
$tunnelError = Join-Path $repository "tmp\cloudflared-err.log"
$serverOut = Join-Path $repository "tmp\public-preview-server-out.log"
$serverError = Join-Path $repository "tmp\public-preview-server-err.log"
$statusPath = Join-Path $repository "tmp\public-preview.json"
$startLockPath = Join-Path $repository "tmp\public-preview-start.lock"

function New-PreviewStartLock {
  try {
    return [System.IO.File]::Open(
      $startLockPath,
      [System.IO.FileMode]::CreateNew,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None
    )
  } catch [System.IO.IOException] {
    $existingLock = Get-Item -LiteralPath $startLockPath -ErrorAction SilentlyContinue
    if ($existingLock -and ((Get-Date) - $existingLock.LastWriteTime).TotalMinutes -gt 5) {
      Remove-Item -LiteralPath $startLockPath -Force
      return [System.IO.File]::Open(
        $startLockPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
      )
    }
    throw "A public preview start is already running"
  }
}

$startLock = New-PreviewStartLock
try {

foreach ($file in @($RubyPath, $database, $cloudflared)) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    throw "Required file not found: $file"
  }
}

function Stop-VerifiedProcess([int]$ProcessId, [string]$Name, [string]$CommandPattern) {
  $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if (-not $process) { return }
  $command = (Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId").CommandLine
  if ($process.ProcessName -ne $Name -or $command -notmatch $CommandPattern) {
    throw "Refusing to stop unexpected process $ProcessId ($($process.ProcessName))"
  }
  Stop-Process -Id $ProcessId -Force
}

$existingTunnel = Get-CimInstance Win32_Process |
  Where-Object { $_.Name -eq "cloudflared.exe" -and $_.CommandLine -like "*$cloudflared*" }
foreach ($process in $existingTunnel) {
  Stop-VerifiedProcess $process.ProcessId "cloudflared" "cloudflared\.exe.*tunnel"
}

$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
  Select-Object -First 1
if ($listener) {
  Stop-VerifiedProcess $listener.OwningProcess "ruby" "bin[/\\]rails server"
}
Start-Sleep -Seconds 2

Remove-Item -LiteralPath $tunnelOut, $tunnelError, $serverOut, $serverError -Force -ErrorAction SilentlyContinue
$tunnel = Start-Process -FilePath $cloudflared `
  -ArgumentList "tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:$Port", "--http-host-header", "localhost" `
  -WorkingDirectory $repository -WindowStyle Hidden `
  -RedirectStandardOutput $tunnelOut -RedirectStandardError $tunnelError -PassThru

$deadline = (Get-Date).AddSeconds(60)
do {
  Start-Sleep -Seconds 2
  $tunnelLog = ((Get-Content $tunnelOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content $tunnelError -Raw -ErrorAction SilentlyContinue))
  $urlMatch = [regex]::Match($tunnelLog, "https://[a-z0-9-]+\.trycloudflare\.com")
} while (-not $urlMatch.Success -and (Get-Date) -lt $deadline)
if (-not $urlMatch.Success) {
  Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue
  throw "Cloudflare did not issue a public URL within 60 seconds"
}

$publicUrl = $urlMatch.Value
$publicHost = ([Uri]$publicUrl).Host
$env:Path = "$(Split-Path -Parent $RubyPath);$env:Path"
$env:STOCK_DATABASE = $database
$env:PUBLIC_TUNNEL_HOST = $publicHost
$env:PUBLIC_PREVIEW = "1"
$env:ASSET_CACHE_PATH = "memory"
$server = Start-Process -FilePath $RubyPath `
  -ArgumentList "bin/rails", "server", "-p", $Port, "-b", "127.0.0.1" `
  -WorkingDirectory $repository -WindowStyle Hidden `
  -RedirectStandardOutput $serverOut -RedirectStandardError $serverError -PassThru

$deadline = (Get-Date).AddSeconds(120)
do {
  Start-Sleep -Seconds 3
  $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
} while (-not $listener -and (Get-Date) -lt $deadline)
if (-not $listener) {
  Stop-Process -Id $server.Id, $tunnel.Id -Force -ErrorAction SilentlyContinue
  throw "Rails did not listen on port $Port within 120 seconds"
}

$localResponse = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/sz" -TimeoutSec 60
$publicResponse = Invoke-WebRequest -UseBasicParsing -Uri "$publicUrl/sz" -TimeoutSec 60
if ($localResponse.StatusCode -ne 200 -or $publicResponse.StatusCode -ne 200) {
  throw "Preview health check failed (local=$($localResponse.StatusCode), public=$($publicResponse.StatusCode))"
}

$status = @{
  url = $publicUrl
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  rails_pid = ($listener | Select-Object -First 1).OwningProcess
  tunnel_pid = $tunnel.Id
  database = $database
}
$status | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
Write-Output ([pscustomobject]$status)
} finally {
  $startLock.Dispose()
  Remove-Item -LiteralPath $startLockPath -Force -ErrorAction SilentlyContinue
}
