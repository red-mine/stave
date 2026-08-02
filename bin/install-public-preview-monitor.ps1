param(
  [string]$TaskName = "Stock Stave Public Preview Monitor",
  [int]$IntervalMinutes = 30
)

$ErrorActionPreference = "Stop"
$monitor = Join-Path $PSScriptRoot "ensure-public-preview.ps1"
$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
$interval = [Math]::Max($IntervalMinutes, 5)

$action = New-ScheduledTaskAction `
  -Execute $pwsh `
  -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$monitor`""
$trigger = New-ScheduledTaskTrigger `
  -Once -At (Get-Date).AddMinutes(1) `
  -RepetitionInterval (New-TimeSpan -Minutes $interval)
$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
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
  -Description "Check Stock Stave public preview health twice before safely recovering it." `
  -Force | Out-Null

Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
