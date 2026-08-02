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
