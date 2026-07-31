require "test_helper"

class StockCalculationTest < ActiveSupport::TestCase
  class StockWithData < Stock::Stock
    def initialize(prices)
      super(Stock::SZSTK, Stock::STAVE)
      start_date = Date.new(2024, 1, 1)
      @data = prices.each_with_index.map do |price, index|
        { date: start_date + index, price: price, index: index }
      end
    end

    private

    def _good_data(_stock)
      @data.map(&:dup)
    end
  end

  test "moving average uses each complete window" do
    engine = StockWithData.new([])

    assert_equal [2.0, 3.0, 4.0], engine.send(:_good_move, [1, 2, 3, 4, 5], 3)
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
end
