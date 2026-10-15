$ErrorActionPreference = "Stop"
# bin/ holds the scheduled automation, but the repository root holds the
# hand-run ones (install, stocks, cred), and a syntax error there is only found
# when someone is already trying to recover. Parse both.
$directories = @($PSScriptRoot, (Split-Path -Parent $PSScriptRoot))
$scripts = foreach ($directory in $directories) {
  Get-ChildItem -LiteralPath $directory -Filter "*.ps1" -File
}
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
