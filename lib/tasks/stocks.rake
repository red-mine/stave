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

  database = ActiveRecord::Base.connection_db_config.database
  if database && File.file?(database)
    backup_dir = Rails.root.join("tmp", "backups")
    FileUtils.mkdir_p(backup_dir)
    backup = backup_dir.join("stock-#{Time.current.strftime('%Y%m%d-%H%M%S')}.sqlite3")
    FileUtils.cp(database, backup)
    puts "Database backup: #{backup}"
  end

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

desc "stock"
task :stock => :environment do
  puts "stock"
  puts "#{Stock::VERSION}"
  puts "#{RUBY_PLATFORM}"
end
