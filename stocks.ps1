$db = ".\db\stock.sqlite3"
if (Test-Path $db) {
  Remove-Item -r -force $db
}
rails db:migrate

rails lohas[sz]
rails years[sz]
rails stave[sz]

rails lohas[sh]
rails years[sh]
rails stave[sh]
