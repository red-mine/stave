param(
  [string]$TaskName = "Stock Stave Daily Refresh",
  [string]$At = "20:30"
)

$ErrorActionPreference = "Stop"
$runner = Join-Path $PSScriptRoot "daily-refresh.ps1"
$time = [DateTime]::ParseExact($At, "HH:mm", [Globalization.CultureInfo]::InvariantCulture)
$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source

$action = New-ScheduledTaskAction `
  -Execute $pwsh `
  -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$runner`" -RunSource scheduled"
$trigger = New-ScheduledTaskTrigger -Daily -At $time
$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Hours 4)
$principal = New-ScheduledTaskPrincipal `
  -UserId $env:USERNAME `
  -LogonType Interactive `
  -RunLevel Limited

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -Principal $principal `
  -Description "Refresh Stock Stave data and record signal snapshots every evening." `
  -Force | Out-Null

$registeredTask = Get-ScheduledTask -TaskName $TaskName
$taskInfo = $registeredTask | Get-ScheduledTaskInfo
$repository = Split-Path -Parent $PSScriptRoot
$statusPath = Join-Path $repository "tmp\stock-refresh-schedule.json"
@{
  task_name = $TaskName
  time = $time.ToString("HH:mm")
  enabled = $registeredTask.State -ne "Disabled"
  installed_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8

$taskInfo
