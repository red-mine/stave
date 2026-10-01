require "test_helper"
require "stringio"
require "tempfile"

class StockCalculationTest < ActiveSupport::TestCase
  class StockWithData < Stock::Stock
    attr_reader :data_reads

    def initialize(prices)
      super(Stock::SZSTK, Stock::STAVE)
      @data_reads = 0
      start_date = Date.new(2024, 1, 1)
      @data = prices.each_with_index.map do |price, index|
        { date: start_date + index, price: price, index: index }
      end
    end

    private

    def _data(_stock)
      @data_reads += 1
      @data.map(&:dup)
    end

    def _model_data(_stock)
      [@data.map { |record| record[:price] }, @data.last&.fetch(:date)]
    end
  end

  class StockWithFile < Stock::Stock
    def initialize(path, trim: 0)
      super(Stock::SZSTK, Stock::STAVE, trim: trim)
      @path = path
    end

    private

    def _path(_stock)
      @path
    end
  end

  class StockForResume < Stock::Stock
    attr_reader :model_calls

    def initialize
      super(Stock::SZSTK, Stock::STAVE)
      @model_calls = []
    end

    private

    def _stocks
      ["current", "pending"]
    end

    def _last_date(_stock)
      Date.new(2026, 7, 31)
    end

    def _model(stock)
      @model_calls << stock
      { stock: stock, coef: 1.0 }
    end
  end

  test "moving average uses each complete window" do
    engine = StockWithData.new([])

    assert_equal [2.0, 3.0, 4.0], engine.send(:_move, [1, 2, 3, 4, 5], 3)
  end

  test "decodes TongdaXin date and closing price from a binary record" do
    engine = StockWithData.new([])
    record = [20_260_731, 1_234, 1_300, 1_200, 1_255].pack("L<5") + "\0" * 12

    decoded = engine.send(:_read_record, StringIO.new(record), 7)

    assert_equal Date.new(2026, 7, 31), decoded[:date]
    assert_equal 12.55, decoded[:price]
    assert_equal 7, decoded[:index]
  end

  test "reads the required history from one binary file block" do
    Tempfile.create(["stock", ".day"], binmode: true) do |file|
      start_date = Date.new(2025, 1, 1)
      (Stock::STAVE * 2 + 1).times do |index|
        date = start_date + index
        encoded_date = date.year * 10_000 + date.month * 100 + date.day
        file.write([encoded_date, 0, 0, 0, 1_000 + index].pack("L<5") + "\0" * 12)
      end
      file.flush

      data = StockWithFile.new(file.path).send(:_data, "TEST")

      assert_equal Stock::STAVE * 2, data.length
      assert_equal start_date + 1, data.first[:date]
      assert_equal 10.01, data.first[:price]
      assert_equal start_date + Stock::STAVE * 2, data.last[:date]
    end
  end

  test "trim reproduces the result of a physically truncated file" do
    Tempfile.create(["stock", ".day"], binmode: true) do |file|
      start_date = Date.new(2025, 1, 1)
      total_records = Stock::STAVE * 2 + 10
      total_records.times do |index|
        date = start_date + index
        encoded_date = date.year * 10_000 + date.month * 100 + date.day
        file.write([encoded_date, 0, 0, 0, 1_000 + index].pack("L<5") + "\0" * 12)
      end
      file.flush

      trim = 7
      truncated_path = "#{file.path}.truncated"
      File.binwrite(truncated_path, File.binread(file.path, (total_records - trim) * 32))

      begin
        trimmed = StockWithFile.new(file.path, trim: trim).send(:_data, "TEST")
        truncated = StockWithFile.new(truncated_path).send(:_data, "TEST")

        refute_empty trimmed
        assert_equal truncated, trimmed
      ensure
        File.delete(truncated_path)
      end
    end
  end

  test "trim beyond available history returns no data instead of raising" do
    Tempfile.create(["stock", ".day"], binmode: true) do |file|
      start_date = Date.new(2025, 1, 1)
      total_records = Stock::STAVE * 2 + 5
      total_records.times do |index|
        date = start_date + index
        encoded_date = date.year * 10_000 + date.month * 100 + date.day
        file.write([encoded_date, 0, 0, 0, 1_000 + index].pack("L<5") + "\0" * 12)
      end
      file.flush

      assert_equal Stock::STAVE * 2, StockWithFile.new(file.path, trim: 4).send(:_data, "TEST").length
      assert_empty StockWithFile.new(file.path, trim: 5).send(:_data, "TEST")
      assert_equal [[], nil], StockWithFile.new(file.path, trim: 10).send(:_model_data, "TEST")
      assert_nil StockWithFile.new(file.path, trim: total_records).send(:_last_date, "TEST")
    end
  end

  test "builds market paths below the configured TongdaXin root" do
    engine = StockWithData.new([])

    Stock.stub(:data_root, Pathname.new("C:/market-data/vipdoc")) do
      expected = File.join("C:/market-data/vipdoc", Stock::SZSTK, "lday") + File::SEPARATOR

      assert_equal expected, engine.send(:_base)
    end
  end

  test "data_root uses vipdoc on Linux and Windows path otherwise" do
    if RUBY_PLATFORM.include?("linux")
      assert_equal Pathname.new("vipdoc").expand_path, Stock.data_root
      refute_match %r{C:/new_tdx/vipdoc}, Stock.data_root.to_s
    else
      assert_equal Pathname.new("C:/new_tdx/vipdoc").expand_path, Stock.data_root
    end
  end

  test "resumable model generation skips rows with the current source date" do
    current_date = Date.new(2026, 7, 31)
    relation = Minitest::Mock.new
    relation.expect(:pluck, [["current", current_date]], [:stock, :date])
    table = Minitest::Mock.new
    table.expect(:where, relation, [], area: Stock::SZSTK, years: Stock::STAVE)
    engine = StockForResume.new

    engine.models(table)

    assert_equal ["pending"], engine.model_calls
    table.verify
    relation.verify
  end

  test "positive linear prices produce an aligned regression trend" do
    prices = Array.new(Stock::STAVE * 2) { |index| 10.0 + index * 0.2 }
    engine = StockWithData.new(prices)
    trend = engine.trend("TEST")

    assert_equal Stock::STAVE + 1, trend.length
    assert_in_delta prices[Stock::STAVE - 1], trend.first.last, 0.01
    assert_in_delta prices.last, trend.last.last, 0.01
  end

  test "exactly linear prices have zero-width stave deviation" do
    prices = Array.new(Stock::STAVE * 2) { |index| 20.0 + index * 0.25 }
    engine = StockWithData.new(prices)

    assert_equal engine.trend("TEST"), engine.stave_band("TEST", true, 2)
    assert_equal engine.trend("TEST"), engine.stave_band("TEST", false, 2)
  end

  test "non-positive trends are excluded from eligible models" do
    falling_prices = Array.new(Stock::STAVE * 2) { |index| 200.0 - index * 0.25 }
    engine = StockWithData.new(falling_prices)

    assert_empty engine.send(:_model, "TEST")
  end

  test "latest signal is calculated from one history read" do
    prices = Array.new(Stock::STAVE * 2) { |index| 20.0 + index * 0.25 }
    engine = StockWithData.new(prices)
    model = engine.send(:_model, "TEST")

    result = engine.send(:_price, model)

    assert_equal false, result[0]
    assert_equal 1, result[2]
    assert_nil result[3]
    assert_equal 1, engine.data_reads
  end

  test "single-pass latest signal matches the legacy series calculations" do
    prices = Array.new(Stock::STAVE * 2) do |index|
      30.0 + index * 0.08 + Math.sin(index.fdiv(7)) * 2
    end
    engine = StockWithData.new(prices)
    model = engine.send(:_model, "TEST")
    legacy = StockWithData.new(prices)
    stock = "TEST"
    boll = legacy.aver(stock, Stock::STAVE)[-1][1]
    mup = legacy.boll(stock, Stock::STAVE, true)[-1][1]
    mdn = legacy.boll(stock, Stock::STAVE, false)[-1][1]
    trend = legacy.trend(stock)[-1][1]
    up1 = legacy.stave_band(stock, true, 1)[-1][1]
    dn1 = legacy.stave_band(stock, false, 1)[-1][1]
    up2 = legacy.stave_band(stock, true, 2)[-1][1]
    dn2 = legacy.stave_band(stock, false, 2)[-1][1]
    expected = legacy.send(
      :_signal, model[:price],
      boll: boll, mup: mup, mdn: mdn, trend: trend,
      up1: up1, dn1: dn1, up2: up2, dn2: dn2
    )

    assert_equal expected, engine.send(:_price, model)
    assert_equal 1, engine.data_reads
  end
end

class StockResultTest < ActiveSupport::TestCase
  LOHAS_DATE = Date.new(2026, 8, 31)

  # staves writes from the models models() built, and valid_model? judges one,
  # so both need a price history. This supplies one in place of .day files,
  # which lets _model's branches be reached without binary fixtures.
  class StockWithPrices < Stock::Stock
    def initialize(prices)
      super(Stock::SZSTK, Stock::STAVE)
      start_date = Date.new(2024, 1, 1)
      @data = prices.each_with_index.map do |price, index|
        { date: start_date + index, price: price, index: index }
      end
    end

    private

    def _stocks
      ["sz000001"]
    end

    def _data(_stock)
      @data.map(&:dup)
    end

    def _model_data(_stock)
      [@data.map { |record| record[:price] }, @data.last&.fetch(:date)]
    end
  end

  private

  # result pairs a stock's LOHAS row with its year row and writes one
  # StocksCoefsStav, so both halves have to exist for the stock to appear.
  def pair(stock, area: Stock::SZSTK)
    StocksCoefsLoha.create!(stock: stock, area: area, coef: 0.05, price: 12.5,
      stave: "BUY4", boll: 3, stav: 2, date: LOHAS_DATE, years: Stock::LOHAS)
    StocksCoefsYear.create!(stock: stock, area: area, coef: 0.08, price: 12.5,
      stave: "SEL3", boll: 1, stav: 4, date: LOHAS_DATE, years: Stock::YEARS)
  end

  test "result joins a stock's LOHAS row and year row into one signal row" do
    pair("sz000001")

    Stock::Stock.new(Stock::SZSTK, Stock::STAVE).result

    stav = StocksCoefsStav.find_by(stock: "sz000001", area: Stock::SZSTK)
    assert_equal 0.05, stav.loha
    assert_equal 0.08, stav.year
    assert_equal "BUY4", stav.lohas_signal
    assert_equal "SEL3", stav.year_signal
    assert_equal 3, stav.boll3
    assert_equal 2, stav.stav3
    assert_equal 1, stav.boll1
    assert_equal 4, stav.stav1
    assert_equal 12.5, stav.price
    assert_equal LOHAS_DATE, stav.date
  end

  test "result leaves out a stock that has no year row" do
    StocksCoefsLoha.create!(stock: "sz000002", area: Stock::SZSTK, coef: 0.05,
      price: 12.5, date: LOHAS_DATE)

    Stock::Stock.new(Stock::SZSTK, Stock::STAVE).result

    assert_nil StocksCoefsStav.find_by(stock: "sz000002", area: Stock::SZSTK)
  end

  test "result writes only for its own market" do
    pair("sz000001", area: Stock::SZSTK)
    pair("sh600000", area: Stock::SHSTK)

    Stock::Stock.new(Stock::SZSTK, Stock::STAVE).result

    assert StocksCoefsStav.exists?(stock: "sz000001", area: Stock::SZSTK)
    assert_empty StocksCoefsStav.where(stock: "sh600000")
  end

  test "a second result run updates the row instead of adding one" do
    pair("sz000001")

    Stock::Stock.new(Stock::SZSTK, Stock::STAVE).result
    StocksCoefsLoha.find_by!(stock: "sz000001", area: Stock::SZSTK).update!(stave: "WAT9", coef: 0.06)
    Stock::Stock.new(Stock::SZSTK, Stock::STAVE).result

    assert_equal 1, StocksCoefsStav.where(stock: "sz000001", area: Stock::SZSTK).count
    stav = StocksCoefsStav.find_by(stock: "sz000001", area: Stock::SZSTK)
    assert_equal "WAT9", stav.lohas_signal
    assert_equal 0.06, stav.loha
  end

  test "staves writes each model's own values to the table" do
    prices = Array.new(Stock::STAVE * 2) { |index| 30.0 + index * 0.08 + Math.sin(index.fdiv(7)) * 2 }
    engine = StockWithPrices.new(prices)

    engine.models
    engine.staves(StocksCoefsLoha)

    model = engine.models.first
    row = StocksCoefsLoha.find_by(stock: "sz000001", area: Stock::SZSTK)
    assert_equal Stock::STAVE, row.years
    assert_equal model[:price], row.price
    assert_equal model[:date], row.date
    assert_equal model[:coef], row.coef
  end

  # valid_model? is the gate Stave#result uses to decide whether a stock is
  # worth a signal row at all, so its thresholds are what keep the index from
  # filling up with stocks that are going nowhere.
  test "a stock trending up steeply enough is a valid model" do
    prices = Array.new(Stock::STAVE * 2) { |index| 20.0 + index * 0.05 }
    assert StockWithPrices.new(prices).valid_model?("sz000001")
  end

  test "a stock rising too slowly is not a valid model" do
    prices = Array.new(Stock::STAVE * 2) { |index| 20.0 + index * 0.0001 }
    refute StockWithPrices.new(prices).valid_model?("sz000001")
  end

  test "a flat series is not a valid model" do
    prices = Array.new(Stock::STAVE * 2) { 20.0 }
    refute StockWithPrices.new(prices).valid_model?("sz000001")
  end

  test "a stock with no price history is not a valid model" do
    refute StockWithPrices.new([]).valid_model?("sz000001")
  end
end
