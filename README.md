# Stock Stave

Stock Stave is a Ruby on Rails application for analysing Chinese A-share prices
with the LOHAS Five-Line Stave strategy. It calculates regression trend bands,
a 20-week price channel, and combined buy/sell/wait classifications for
Shenzhen, Shanghai, and Beijing stocks.

See [docs/lohas_stave_strategy.md](docs/lohas_stave_strategy.md) for the strategy,
signal definitions, and known limitations.

## Requirements

- Ruby 3.2.1
- Bundler 2.5.3
- RubyInstaller's MSYS2 development kit on Windows
- SQLite 3 (provided by the bundled Windows gem)
- TongdaXin daily price files for real stock calculations

On Windows, install the `Ruby+Devkit 3.2.1-1 (x64)` RubyInstaller package. If
native gems fail because `yaml.h` is missing, run this from an administrator
PowerShell:

```powershell
C:\Ruby32-x64\bin\ridk.cmd exec pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-libyaml
```

## Setup

From PowerShell in the repository directory:

```powershell
gem install bundler -v 2.5.3
bundle install
bundle exec rails db:migrate
```

The environments use separate databases:

- Development and production: `db/stock.sqlite3`
- Test: `db/test.sqlite3`

## Price data

Set `TDX_DATA_PATH` to the TongdaXin `vipdoc` directory. For example, in
PowerShell:

```powershell
$env:TDX_DATA_PATH = "C:\new_tdx\vipdoc"
```

When the variable is not set, the calculation engine uses:

- Windows: `C:/new_tdx/vipdoc/<area>/lday/`
- Linux: `vipdoc/<area>/lday/`

`<area>` is `sz`, `sh`, or `bj`. Each stock needs enough history for the chosen
window plus the 20-week channel.

## Generate analysis data

Refresh all three markets with one command:

```powershell
bundle exec rails refresh
```

The task validates every source directory before changing data, saves a
timestamped database backup under `tmp/backups`, and safely resumes stocks that
already have the latest source date. To refresh selected markets only:

```powershell
bundle exec rails "refresh[sz,sh]"
```

Verify source freshness, imported dates, row counts, and chart coverage:

```powershell
bundle exec rails data_status
```

The status task exits unsuccessfully when any market stage is missing or stale,
so it can also be used by scheduled jobs and CI.

The individual stages remain available for diagnostics:

```powershell
bundle exec rails "lohas[sz]"
bundle exec rails "years[sz]"
bundle exec rails "stave[sz]"
```

Repeat with `sh` or `bj` as required.

## Run the web application

```powershell
bundle exec rails server
```

Open <http://localhost:3000/sz>, `/sh`, or `/bj`. Select a stock to view its
one-year and 3.5-year stave and channel charts.

## Tests

Prepare the isolated test database once, then run the suite:

```powershell
$env:RAILS_ENV = "test"
bundle exec rails db:migrate
Remove-Item Env:RAILS_ENV
bundle exec rails test
```

The tests cover market routing, configurable data paths, resumable imports,
binary decoding, moving averages, regression alignment, stave deviation, trend
eligibility, and every currently reachable signal code.
