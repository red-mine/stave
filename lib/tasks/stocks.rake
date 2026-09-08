desc "lohas"
task :lohas, [:area, :days] => :environment do |task, args|
  area = unless args.area.nil? then args.area else Stock::SZSTK end
  days = unless args.days.nil? then args.days else Stock::LOHAS end
  stock = Stock::Stock.new(area, days)
  stock.good_models(StocksCoefsLoha)
  stock.good_staves(StocksCoefsLoha)
end

desc "years"
task :years, [:area, :days] => :environment do |task, args|
  area = unless args.area.nil? then args.area else Stock::SZSTK end
  days = unless args.days.nil? then args.days else Stock::YEARS end
  stock = Stock::Stock.new(area, days)
  stock.good_models(StocksCoefsYear)
  stock.good_staves(StocksCoefsYear)
end

desc "stave"
task :stave, [:area, :days] => :environment do |task, args|
  area = unless args.area.nil? then args.area else Stock::SZSTK end
  days = unless args.days.nil? then args.days else Stock::STAVE end
  stock = Stock::Stock.new(area, days)
  stave = Stock::Stave.new(area, days)
  stock.good_result()
  stave.good_result()
end

desc "Create and verify a retained backup of the active SQLite database"
task database_backup: :environment do
  connection = ActiveRecord::Base.connection
  database = ActiveRecord::Base.connection_db_config.database
  if connection.adapter_name == "SQLite" && database && File.file?(database)
    backup_dir = Rails.root.join("tmp", "backups")
    FileUtils.mkdir_p(backup_dir)
    backup = backup_dir.join("stock-#{Time.current.strftime('%Y%m%d-%H%M%S-%L')}.sqlite3")
    Stock::DatabaseBackup.new(connection: connection).call(backup)
    puts "Database backup: #{backup}"
    keep = ENV.fetch("STOCK_BACKUP_KEEP", "7").to_i
    pruned = Stock::DatabaseBackup.prune(backup_dir, keep: keep)
    puts "Pruned #{pruned} old backup(s); keeping the newest #{[keep, 1].max}" if pruned.positive?
  end
end

desc "Refresh analysis data for all markets (or a selected market list)"
task :refresh, [:area1, :area2, :area3] => :environment do |_task, args|
  supported_areas = Stock::AREAS
  areas = args.to_a.compact.map(&:strip).uniq
  areas = supported_areas if areas.empty?
  invalid_areas = areas - supported_areas
  abort "Unsupported market(s): #{invalid_areas.join(', ')}" unless invalid_areas.empty?

  missing_paths = areas.reject do |area|
    File.directory?(File.join(Stock.data_root, area, "lday"))
  end
  unless missing_paths.empty?
    abort "Missing TongdaXin data for: #{missing_paths.join(', ')} under #{Stock.data_root}"
  end

  Rake::Task[:database_backup].invoke

  areas.each do |area|
    puts "Refreshing #{area}..."
    lohas = Stock::Stock.new(area, Stock::LOHAS)
    lohas.good_models(StocksCoefsLoha)
    lohas.good_staves(StocksCoefsLoha)

    years = Stock::Stock.new(area, Stock::YEARS)
    years.good_models(StocksCoefsYear)
    years.good_staves(StocksCoefsYear)

    Stock::Stock.new(area, Stock::STAVE).good_result
    Stock::Stave.new(area, Stock::STAVE).good_result
    puts "Finished #{area}."
  end
end

desc "Report TongdaXin source and generated-data health"
task data_status: :environment do
  checker = Stock::DataStatus.new
  report = checker.call

  report.each do |area, market|
    state = market[:healthy] ? "OK" : "INCOMPLETE"
    puts "#{area.upcase}: #{state} source=#{market[:source_date] || 'missing'}"
    market[:tables].each do |table, status|
      puts "  #{table}: rows=#{status[:rows]} stocks=#{status[:stocks]} latest=#{status[:date] || 'missing'}"
    end
  end

  abort "Stock data is incomplete" unless checker.healthy?(report)
end

desc "Refresh only markets with new or incomplete data, then verify and snapshot them"
task daily_refresh: :environment do
  begin
    $stdout.sync = true
    Stock::RefreshRun.new.call do
      Rake::Task[:database_backup].invoke
      progress = lambda do |area, state|
        message = state == :started ? "Checking #{area.upcase} market data..." : "Finished checking #{area.upcase}."
        puts message
      end
      checker = Stock::DataStatus.new(progress: progress)
      report = checker.call
      areas = checker.refresh_areas(report)

      if areas.empty?
        latest = report.values.filter_map { |market| market[:source_date] }.max
        puts "No refresh needed. All markets are healthy through #{latest || 'an unavailable date'}."
      else
        puts "Markets requiring refresh: #{areas.map(&:upcase).join(', ')}"
        Rake::Task[:refresh].reenable
        Rake::Task[:refresh].invoke(*areas)

        verified = checker.call
        abort "Refresh finished but generated data remains incomplete" unless checker.healthy?(verified)
      end

      captured = Stock::AREAS.to_h { |area| [area, Stock::SignalSnapshot.capture!(area)] }
      missing = captured.select { |_area, rows| rows.zero? }.keys
      abort "Snapshot capture produced no rows for: #{missing.map(&:upcase).join(', ')}" if missing.any?

      stored = StockSignalSnapshot.group(:area).count
      puts "Daily refresh complete. Captured rows: #{captured.sort.to_h.inspect}. Stored history rows: #{stored.sort.to_h.inspect}"
    end
  rescue Stock::RefreshRun::AlreadyRunning => error
    abort error.message
  end
end

desc "Preview which markets daily_refresh would recalculate without changing data"
task refresh_plan: :environment do
  checker = Stock::DataStatus.new
  report = checker.call
  areas = checker.refresh_areas(report)

  report.each do |area, market|
    state = market[:healthy] ? "healthy" : "needs refresh"
    puts "#{area.upcase}: #{state} source=#{market[:source_date] || 'missing'}"
  end
  puts areas.empty? ? "No database changes are needed." : "Would refresh: #{areas.map(&:upcase).join(', ')}"
end

desc "Report saved daily signal-history coverage"
task snapshot_status: :environment do
  Stock::AREAS.each do |area|
    snapshots = StockSignalSnapshot.where(area: area)
    puts "#{area.upcase}: rows=#{snapshots.count} dates=#{snapshots.distinct.count(:signal_date)} latest=#{snapshots.maximum(:signal_date) || 'missing'}"
  end
end

desc "Report stocks whose latest coefficient date trails the market date"
task stale_stocks: :environment do
  Stock::AREAS.each do |area|
    market_date = StocksCoefsStav.where(area: area).maximum(:date)
    next unless market_date

    lagging = StocksCoefsStav.where(area: area).where.not(date: market_date).order(:date, :stock)
    total = StocksCoefsStav.where(area: area).count
    puts "#{area.upcase}: #{lagging.count} of #{total} stocks trail #{market_date}"
    lagging.each do |record|
      puts "  #{record.stock} date=#{record.date} lohas=#{record.lohas.inspect} years=#{record.years.inspect}"
    end
  end
end

desc "stock"
task :stock => :environment do
  puts "stock"
  puts "#{Stock::VERSION}"
  puts "#{RUBY_PLATFORM}"
end

desc "Backtest signal performance across multiple horizons and signal types"
task :backtest, [:area] => :environment do |_task, args|
  area = args.area || Stock::SZSTK
  horizons = [5, 20, 60, 120]
  signal_types = [:buy, :sell]

  puts "=" * 60
  puts "Signal backtest for #{area.upcase}"
  puts "=" * 60

  signal_types.each do |signal_type|
    puts "\n## #{signal_type.to_s.upcase} SIGNALS"
    puts "-" * 40

    horizons.each do |horizon|
      report = Stock::SignalPerformance.new(area, horizon: horizon).call(signal_type: signal_type)

      unless report.ready
        puts "  #{horizon}d: Not enough data (#{report.dates} dates, need #{Stock::SignalPerformance::MINIMUM_DATES}+)"
        next
      end

      puts "  #{horizon}d horizon (#{report.dates} trading dates):"

      if report.cohorts.empty?
        puts "    No cohorts met minimum sample size (#{Stock::SignalPerformance::MINIMUM_SAMPLE})"
        next
      end

      report.cohorts.each do |cohort|
        label = "#{cohort.year_signal} + #{cohort.lohas_signal}"
        label += " [#{cohort.trend_group}]" if cohort.trend_group
        puts "    #{label.ljust(20)} n=#{cohort.sample_size.to_s.ljust(4)} win=#{cohort.win_rate.to_s.rjust(5)}%  avg_ret=#{cohort.average_return.to_s.rjust(7)}%  avg_dd=#{cohort.average_drawdown.to_s.rjust(7)}%"
      end
    end
  end

  puts "\n" + "=" * 60
  puts "Note: Returns are not annualized. Transaction costs are not deducted."
  puts "      Overlapping holding periods are included in the sample."
end

desc "Simulate following the buy/sell recommendation on every historical day"
task :simulate_strategy, [:area] => :environment do |_task, args|
  area = args.area || Stock::SZSTK
  result = Stock::StrategySimulation.new(area).call

  puts "=" * 60
  puts "Strategy simulation for #{area.upcase}"
  puts "=" * 60

  if result.ready
    puts "Trading dates:     #{result.dates}"
    puts "Starting cash:     #{format('%.2f', result.starting_cash)}"
    puts "Final equity:      #{format('%.2f', result.final_equity)}"
    puts "Total return:      #{result.total_return}%"
    puts "Max drawdown:      #{result.max_drawdown}%"
    puts

    if result.trades.any?
      wins = result.trades.count { |trade| trade.return_pct.positive? }
      avg_hold = result.trades.sum { |trade| (trade.exit_date - trade.entry_date).to_i }.fdiv(result.trades.size)
      puts "Trades closed:     #{result.trades.size}"
      puts "Win rate:          #{(wins.fdiv(result.trades.size) * 100).round(2)}%"
      puts "Avg holding days:  #{avg_hold.round(1)}"
    else
      puts "No trades were closed."
    end

    puts
    puts "Equity curve (sampled):"
    step = [(result.equity_curve.size / 10.0).ceil, 1].max
    checkpoints = result.equity_curve.each_slice(step).map(&:first)
    checkpoints << result.equity_curve.last unless checkpoints.last == result.equity_curve.last
    checkpoints.each { |point| puts "  #{point.date}: #{format('%.2f', point.equity)}" }
  else
    puts "No signal history available for #{area.upcase}."
  end

  puts "\n" + "=" * 60
  puts "Note: Equal-weight sizing, no transaction costs, forced exit after"
  puts "      #{Stock::StrategySimulation::MAX_HOLD_DAYS} trading days without a sell signal."
end

desc "Backfill historical signal snapshots for backtesting by replaying LOHAS/YEARS/STAVE against trimmed price history"
task :backfill_signal_history, [:days] => :environment do |_task, args|
  days = (args.days || 63).to_i
  abort "days must be a positive integer" unless days.positive?

  original_config = ActiveRecord::Base.connection_db_config
  production_database = original_config.database
  abort "No active SQLite database found to back up" unless production_database && File.file?(production_database)

  scratch_dir = Rails.root.join("tmp", "backfill")
  FileUtils.mkdir_p(scratch_dir)
  scratch_path = scratch_dir.join("scratch-#{Time.current.strftime('%Y%m%d-%H%M%S-%L')}.sqlite3")

  puts "Cloning #{production_database} to #{scratch_path}..."
  Stock::DatabaseBackup.new.call(scratch_path)

  begin
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: scratch_path.to_s)

    Stock::AREAS.each do |area|
      (1..days).each do |trim|
        StocksCoefsLoha.where(area: area).delete_all
        StocksCoefsYear.where(area: area).delete_all
        StocksCoefsStav.where(area: area).delete_all

        lohas = Stock::Stock.new(area, Stock::LOHAS, trim: trim)
        lohas.good_models(StocksCoefsLoha)
        lohas.good_staves(StocksCoefsLoha)

        years = Stock::Stock.new(area, Stock::YEARS, trim: trim)
        years.good_models(StocksCoefsYear)
        years.good_staves(StocksCoefsYear)

        Stock::Stock.new(area, Stock::STAVE).good_result
        captured = Stock::SignalSnapshot.capture!(area)

        puts "#{area.upcase} trim=#{trim}/#{days}: captured #{captured} row(s)"
      end
    end
  ensure
    ActiveRecord::Base.establish_connection(original_config)
  end

  puts "Merging backfilled snapshots into #{production_database}..."
  connection = ActiveRecord::Base.connection
  connection.execute("ATTACH DATABASE #{connection.quote(scratch_path.to_s)} AS backfill")
  inserted = connection.exec_update(<<~SQL)
    INSERT OR IGNORE INTO stock_signal_snapshots
      (stock, area, signal_date, price, long_trend, year_trend, lohas_signal, year_signal,
       lohas_channel, lohas_stave, year_channel, year_stave, created_at, updated_at)
    SELECT stock, area, signal_date, price, long_trend, year_trend, lohas_signal, year_signal,
           lohas_channel, lohas_stave, year_channel, year_stave, created_at, updated_at
    FROM backfill.stock_signal_snapshots
  SQL
  connection.execute("DETACH DATABASE backfill")
  File.delete(scratch_path)

  puts "Backfill complete. Inserted #{inserted} new signal snapshot row(s)."
end
