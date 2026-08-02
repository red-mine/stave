$ErrorActionPreference = "Stop"
$scripts = Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.ps1" -File
$failures = @()

foreach ($script in $scripts) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile(
    $script.FullName,
    [ref]$tokens,
    [ref]$errors
  )
  foreach ($error in $errors) {
    $failures += "$($script.Name):$($error.Extent.StartLineNumber): $($error.Message)"
  }
}

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ }
  exit 1
}

Write-Output "PowerShell syntax OK ($($scripts.Count) scripts)"
