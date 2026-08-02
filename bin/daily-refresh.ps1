param(
  [string]$RubyPath = "C:\Ruby34-x64\bin\ruby.exe",
  [string]$DatabasePath = "",
  [ValidateSet("manual", "scheduled")]
  [string]$RunSource = "manual",
  [int]$LogRetention = 30
)

$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
$database = if ($DatabasePath) {
  [System.IO.Path]::GetFullPath($DatabasePath)
} else {
  Join-Path $repository "tmp\ui-stock.sqlite3"
}
$logDirectory = Join-Path $repository "log\daily-refresh"
$logFile = Join-Path $logDirectory "latest.log"
$archiveLog = Join-Path $logDirectory "refresh-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff').log"

if (-not (Test-Path -LiteralPath $RubyPath -PathType Leaf)) {
  throw "Ruby executable not found: $RubyPath"
}
if (-not (Test-Path -LiteralPath $database -PathType Leaf)) {
  throw "Stock database not found: $database"
}

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$env:STOCK_DATABASE = $database
$env:STOCK_REFRESH_SOURCE = $RunSource
$env:RAILS_ENV = "development"
$env:RACK_ENV = "development"
$env:Path = "$(Split-Path -Parent $RubyPath);$env:Path"

Push-Location $repository
try {
  "[$(Get-Date -Format o)] Starting daily refresh" | Tee-Object -FilePath $logFile
  & $RubyPath bin\rails daily_refresh 2>&1 | Tee-Object -FilePath $logFile -Append
  if ($LASTEXITCODE -ne 0) {
    throw "Daily refresh failed with exit code $LASTEXITCODE"
  }
  "[$(Get-Date -Format o)] Daily refresh succeeded" | Tee-Object -FilePath $logFile -Append
} catch {
  "[$(Get-Date -Format o)] $($_.Exception.Message)" | Tee-Object -FilePath $logFile -Append
  exit 1
} finally {
  if (Test-Path -LiteralPath $logFile) {
    Copy-Item -LiteralPath $logFile -Destination $archiveLog -Force
  }
  $keep = [Math]::Max($LogRetention, 1)
  Get-ChildItem -LiteralPath $logDirectory -Filter "refresh-*.log" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip $keep |
    Remove-Item -Force
  Pop-Location
}
