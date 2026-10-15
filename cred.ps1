# credentials:edit needs a clean slate, but the encrypted file is the only copy
# of the recorded secrets, so move it aside rather than delete it.
$credentials = ".\config\credentials.yml.enc"
if (Test-Path $credentials) {
  New-Item -ItemType Directory -Force ".\tmp\backups" | Out-Null
  $kept = ".\tmp\backups\credentials-$(Get-Date -Format 'yyyyMMdd-HHmmss').yml.enc"
  $suffix = 1
  while (Test-Path -LiteralPath $kept) {
    $suffix++
    $kept = ".\tmp\backups\credentials-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$suffix.yml.enc"
  }
  Move-Item -LiteralPath $credentials -Destination $kept
  Write-Output "Moved the existing credentials to $kept"
}
$env:EDITOR="code --wait"
rails credentials:edit
