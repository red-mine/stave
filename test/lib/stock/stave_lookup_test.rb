require "test_helper"

class StaveLookupTest < ActiveSupport::TestCase
  test "stock existence is scoped to its market" do
    stock = "shared002"
    StocksCoefsStav.create!(stock: stock, area: Stock::SHSTK)

    assert Stock::Stave.new(Stock::SHSTK, Stock::STAVE).known_stock?(stock)
    refute Stock::Stave.new(Stock::SZSTK, Stock::STAVE).known_stock?(stock)
  end
end
