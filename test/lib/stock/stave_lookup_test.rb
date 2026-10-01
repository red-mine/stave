require "test_helper"

class StaveLookupTest < ActiveSupport::TestCase
  test "stock existence is scoped to its market" do
    stock = "shared002"
    StocksCoefsStav.create!(stock: stock, area: Stock::SHSTK)

    assert Stock::Stave.new(Stock::SHSTK, Stock::STAVE).known_stock?(stock)
    refute Stock::Stave.new(Stock::SZSTK, Stock::STAVE).known_stock?(stock)
  end

  test "index date is the latest result date rather than the highest priced result date" do
    StocksCoefsStav.create!(
      stock: "sh600001", area: Stock::SHSTK, price: 10,
      lohas_signal: "BUY5", date: Date.new(2026, 7, 31)
    )
    StocksCoefsStav.create!(
      stock: "sh600002", area: Stock::SHSTK, price: 100,
      lohas_signal: "BUY5", date: Date.new(2026, 7, 30)
    )

    results, date = Stock::Stave.new(Stock::SHSTK, Stock::STAVE).search(nil)

    assert_equal %w[sh600001 sh600002], results.pluck(:stock)
    assert_equal Date.new(2026, 7, 31), date
  end

  test "searched index retains the market date for freshness comparisons" do
    StocksCoefsStav.create!(
      stock: "sz000522", area: Stock::SZSTK, price: 10,
      lohas_signal: "BUY5", date: Date.new(2013, 3, 13)
    )
    StocksCoefsStav.create!(
      stock: "sz000001", area: Stock::SZSTK, price: 11,
      lohas_signal: "BUY5", date: Date.new(2026, 7, 31)
    )

    results, date = Stock::Stave.new(Stock::SZSTK, Stock::STAVE).search("000522")

    assert_equal ["sz000522"], results.pluck(:stock)
    assert_equal Date.new(2026, 7, 31), date
  end
end

class StaveTrendHealthTest < ActiveSupport::TestCase
  test "a stock with no signal row has no trend health" do
    assert_nil Stock::Stave.new(Stock::SZSTK, Stock::STAVE).trend_health("sz000404")
  end

  test "trend health reads the stock's own market" do
    StocksCoefsStav.create!(stock: "shared003", area: Stock::SHSTK, loha: 0.03)

    assert_nil Stock::Stave.new(Stock::SZSTK, Stock::STAVE).trend_health("shared003")
    refute_nil Stock::Stave.new(Stock::SHSTK, Stock::STAVE).trend_health("shared003")
  end

  test "trend health classifies both windows from the stock's signal row" do
    StocksCoefsStav.create!(stock: "sz000001", area: Stock::SZSTK, loha: 0.03, year: 0.06,
                            date: Date.new(2026, 8, 31))
    health = Stock::Stave.new(Stock::SZSTK, Stock::STAVE).trend_health("sz000001")

    assert_equal Date.new(2026, 8, 31), health[:date]
    assert_equal 0.03, health[:loha_slope]
    assert_equal 0.06, health[:year_slope]
    assert_equal "uptrend", health[:loha_status]
    assert_equal "strong_uptrend", health[:year_status]
  end

  # The bands are the business rule, so each edge is worth pinning: the
  # difference between "flat" and "weak_uptrend" is a single > vs >=.
  test "trend health places each slope in its band" do
    bands = { 0.05 => "strong_uptrend", 0.02 => "uptrend", 0.01 => "flat",
              -0.01 => "flat", -0.02 => "downtrend" }
    stave = Stock::Stave.new(Stock::SZSTK, Stock::STAVE)

    bands.each_with_index do |(slope, expected), index|
      stock = "band#{index}"
      StocksCoefsStav.create!(stock: stock, area: Stock::SZSTK, loha: slope, year: slope)
      assert_equal expected, stave.trend_health(stock)[:loha_status], "slope #{slope}"
    end
  end

  test "an unrecorded slope is not classified" do
    StocksCoefsStav.create!(stock: "sz000002", area: Stock::SZSTK)

    health = Stock::Stave.new(Stock::SZSTK, Stock::STAVE).trend_health("sz000002")
    assert_equal "unknown", health[:loha_status]
  end
end
