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

    def _good_data(_stock)
      @data_reads += 1
      @data.map(&:dup)
    end

    def _good_model_data(_stock)
      [@data.map { |record| record[:price] }, @data.last&.fetch(:date)]
    end
  end

  class StockWithFile < Stock::Stock
    def initialize(path)
      super(Stock::SZSTK, Stock::STAVE)
      @path = path
    end

    private

    def _good_path(_stock)
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

    def _good_stocks
      ["current", "pending"]
    end

    def _good_last_date(_stock)
      Date.new(2026, 7, 31)
    end

    def _good_model(stock)
      @model_calls << stock
      { stock: stock, coef: 1.0 }
    end
  end

  test "moving average uses each complete window" do
    engine = StockWithData.new([])

    assert_equal [2.0, 3.0, 4.0], engine.send(:_good_move, [1, 2, 3, 4, 5], 3)
  end

  test "decodes TongdaXin date and closing price from a binary record" do
    engine = StockWithData.new([])
    record = [20_260_731, 1_234, 1_300, 1_200, 1_255].pack("L<5") + "\0" * 12

    decoded = engine.send(:_good_stock, StringIO.new(record), 7)

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

      data = StockWithFile.new(file.path).send(:_good_data, "TEST")

      assert_equal Stock::STAVE * 2, data.length
      assert_equal start_date + 1, data.first[:date]
      assert_equal 10.01, data.first[:price]
      assert_equal start_date + Stock::STAVE * 2, data.last[:date]
    end
  end

  test "builds market paths below the configured TongdaXin root" do
    engine = StockWithData.new([])

    Stock.stub(:data_root, Pathname.new("C:/market-data/vipdoc")) do
      expected = File.join("C:/market-data/vipdoc", Stock::SZSTK, "lday") + File::SEPARATOR

      assert_equal expected, engine.send(:_good_base)
    end
  end

  test "resumable model generation skips rows with the current source date" do
    current_date = Date.new(2026, 7, 31)
    relation = Minitest::Mock.new
    relation.expect(:pluck, [["current", current_date]], [:stock, :date])
    table = Minitest::Mock.new
    table.expect(:where, relation, [], area: Stock::SZSTK, years: Stock::STAVE)
    engine = StockForResume.new

    engine.good_models(table)

    assert_equal ["pending"], engine.model_calls
    table.verify
    relation.verify
  end

  test "positive linear prices produce an aligned regression trend" do
    prices = Array.new(Stock::STAVE * 2) { |index| 10.0 + index * 0.2 }
    engine = StockWithData.new(prices)
    trend = engine.good_trend("TEST")

    assert_equal Stock::STAVE + 1, trend.length
    assert_in_delta prices[Stock::STAVE - 1], trend.first.last, 0.01
    assert_in_delta prices.last, trend.last.last, 0.01
  end

  test "exactly linear prices have zero-width stave deviation" do
    prices = Array.new(Stock::STAVE * 2) { |index| 20.0 + index * 0.25 }
    engine = StockWithData.new(prices)

    assert_equal engine.good_trend("TEST"), engine.good_stave("TEST", true, 2)
    assert_equal engine.good_trend("TEST"), engine.good_stave("TEST", false, 2)
  end

  test "non-positive trends are excluded from eligible models" do
    falling_prices = Array.new(Stock::STAVE * 2) { |index| 200.0 - index * 0.25 }
    engine = StockWithData.new(falling_prices)

    assert_empty engine.send(:_good_model, "TEST")
  end

  test "latest signal is calculated from one history read" do
    prices = Array.new(Stock::STAVE * 2) { |index| 20.0 + index * 0.25 }
    engine = StockWithData.new(prices)
    model = engine.send(:_good_model, "TEST")

    result = engine.send(:_good_price, model)

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
    model = engine.send(:_good_model, "TEST")
    legacy = StockWithData.new(prices)
    stock = "TEST"
    boll = legacy.good_aver(stock, Stock::STAVE)[-1][1]
    mup = legacy.good_boll(stock, Stock::STAVE, true)[-1][1]
    mdn = legacy.good_boll(stock, Stock::STAVE, false)[-1][1]
    trend = legacy.good_trend(stock)[-1][1]
    up1 = legacy.good_stave(stock, true, 1)[-1][1]
    dn1 = legacy.good_stave(stock, false, 1)[-1][1]
    up2 = legacy.good_stave(stock, true, 2)[-1][1]
    dn2 = legacy.good_stave(stock, false, 2)[-1][1]
    expected = legacy.send(
      :_good_signal, model[:price],
      boll: boll, mup: mup, mdn: mdn, trend: trend,
      up1: up1, dn1: dn1, up2: up2, dn2: dn2
    )

    assert_equal expected, engine.send(:_good_price, model)
    assert_equal 1, engine.data_reads
  end
end
