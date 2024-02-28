bundle
bundle update

rm -f db/stock.sqlite3

rails db:migrate
rails assets:precompile