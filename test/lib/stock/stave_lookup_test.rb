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
      lohas: "BUY5", date: Date.new(2026, 7, 31)
    )
    StocksCoefsStav.create!(
      stock: "sh600002", area: Stock::SHSTK, price: 100,
      lohas: "BUY5", date: Date.new(2026, 7, 30)
    )

    results, date = Stock::Stave.new(Stock::SHSTK, Stock::STAVE).good_index(nil)

    assert_equal %w[sh600001 sh600002], results.pluck(:stock)
    assert_equal Date.new(2026, 7, 31), date
  end
end
