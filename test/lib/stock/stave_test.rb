require "test_helper"

class StaveDataTest < ActiveSupport::TestCase
  test "chart data is market-scoped and ordered chronologically" do
    stock = "shared001"
    StocksStaveYear.create!(stock: stock, area: Stock::SZSTK, years: "price", date: Date.new(2026, 7, 1), price: 12)
    StocksStaveYear.create!(stock: stock, area: Stock::SZSTK, years: "price", date: Date.new(2026, 5, 1), price: 10)
    StocksStaveYear.create!(stock: stock, area: Stock::SHSTK, years: "price", date: Date.new(2026, 6, 1), price: 99)

    _lohas, years, = Stock::Stave.new(Stock::SZSTK, Stock::STAVE).good_data(stock)

    assert_equal [
      [Date.new(2026, 5, 1), 10.0],
      [Date.new(2026, 7, 1), 12.0]
    ], years.first[:data]
  end
end
