module Stock
  class IndexBenchmark
    # TongdaXin price records store the close price as an integer scaled by
    # 100 (matching the decode in Stock::Stock#_good_record); kept as its
    # own constant here since it's a data-format detail, not the same thing
    # as the unrelated Stock::STAVE window-size constant.
    PRICE_SCALE = 100.0
    RECORD_SIZE = 32

    INDEX_CODES = {
      "sz" => "sz399001", # 深证成指
      "sh" => "sh000001"  # 上证综指
    }.freeze

    Result = Data.define(:available, :index_code, :total_return, :prices)

    def initialize(area, dates)
      @area = area
      @dates = dates
    end

    def call
      code = INDEX_CODES[@area]
      return unavailable unless code

      path = ::Stock.data_root.join(@area, "lday", "#{code}.day")
      raw_prices = read_price_series(path)
      return unavailable if raw_prices.empty?

      prices = align(raw_prices)
      first_price = prices[@dates.first]
      last_price = prices[@dates.last]
      return unavailable unless first_price && last_price

      total_return = ((last_price / first_price - 1) * 100).round(2)

      Result.new(available: true, index_code: code, total_return: total_return, prices: prices)
    end

    private

    def unavailable
      Result.new(available: false, index_code: nil, total_return: nil, prices: {})
    end

    def read_price_series(path)
      return {} unless File.file?(path)

      records = File.size(path) / RECORD_SIZE
      prices = {}
      File.open(path, "rb") do |file|
        records.times do
          raw = file.read(RECORD_SIZE)
          values = raw.unpack("L<5")
          date_int = values[0]
          date = Date.new(date_int / 10_000, (date_int / 100) % 100, date_int % 100)
          prices[date] = values[4].fdiv(PRICE_SCALE)
        end
      end
      prices
    end

    # Forward-fills any requested date the index file doesn't have an exact
    # record for, using the most recent known price (mirrors how
    # Stock::StrategySimulation carries a held position's price forward
    # when a stock has no snapshot on a given day).
    def align(raw_prices)
      last_known = nil
      @dates.each_with_object({}) do |date, prices|
        last_known = raw_prices[date] if raw_prices.key?(date)
        prices[date] = last_known if last_known
      end
    end
  end
end
