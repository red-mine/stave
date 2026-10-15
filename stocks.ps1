# The recalculations below want an empty database, but db\stock.sqlite3 holds
# hours of computed coefficients, so move it aside rather than delete it.
$db = ".\db\stock.sqlite3"
if (Test-Path $db) {
  New-Item -ItemType Directory -Force ".\tmp\backups" | Out-Null
  $kept = ".\tmp\backups\stock-discarded-$(Get-Date -Format 'yyyyMMdd-HHmmss').sqlite3"
  $suffix = 1
  while (Test-Path -LiteralPath $kept) {
    $suffix++
    $kept = ".\tmp\backups\stock-discarded-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$suffix.sqlite3"
  }
  Move-Item -LiteralPath $db -Destination $kept
  Write-Output "Moved the existing database to $kept"
}
rails db:migrate

rails lohas[sz]
rails years[sz]
rails stave[sz]

rails lohas[sh]
rails years[sh]
rails stave[sh]
