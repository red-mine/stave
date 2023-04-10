desc "lohas"
task :lohas, [:area, :days] => :environment do |task, args|
  area = unless args.area.nil? then args.area else Stock::SZSTK end
  days = unless args.days.nil? then args.days else Stock::LOHAS end
  stock = Stock::Stock.new(area, days)
  stock.good_models()
  stock.good_staves(StocksCoefsLoha)
end

desc "years"
task :years, [:area, :days] => :environment do |task, args|
  area = unless args.area.nil? then args.area else Stock::SZSTK end
  days = unless args.days.nil? then args.days else Stock::YEARS end
  stock = Stock::Stock.new(area, days)
  stock.good_models()
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

desc "stock"
task :stock => :environment do
  puts "stock"
  puts "#{Stock::VERSION}"
end

desc "openai"
task :openai => :environment do
  OpenAI.configure do |config|
    config.access_token = ENV.fetch('OPENAI_ACCESS_TOKEN')
  end
  client = OpenAI::Client.new
end