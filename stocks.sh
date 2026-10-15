# The recalculations below want an empty database, but db/stock.sqlite3 holds
# hours of computed coefficients, so move it aside rather than delete it.
db=db/stock.sqlite3
if [ -f "$db" ]; then
  mkdir -p tmp/backups
  kept="tmp/backups/stock-discarded-$(date +%Y%m%d-%H%M%S).sqlite3"
  suffix=1
  while [ -e "$kept" ]; do
    suffix=$((suffix + 1))
    kept="tmp/backups/stock-discarded-$(date +%Y%m%d-%H%M%S)-$suffix.sqlite3"
  done
  mv "$db" "$kept"
  echo "Moved the existing database to $kept"
fi

rails db:migrate

rails lohas[sz]
rails years[sz]
rails stave[sz]

rails lohas[sh]
rails years[sh]
rails stave[sh]
