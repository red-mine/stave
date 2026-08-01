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

  test "chart series have unique descriptive labels" do
    lohas, _years, bolls, = Stock::Stave.new(Stock::SZSTK, Stock::STAVE).good_data("labels001")

    assert_equal ["收盘价", "趋势线", "+1SD", "-1SD", "乐观线 (+2SD)", "悲观线 (-2SD)"], lohas.pluck(:name)
    assert_equal ["通道中轨", "通道上轨", "通道下轨"], bolls.drop(1).pluck(:name)
    assert_equal lohas.length, lohas.pluck(:name).uniq.length
    assert_equal bolls.length, bolls.pluck(:name).uniq.length
  end
end
