require "test_helper"

class StockPreviewHealthTest < ActiveSupport::TestCase
  test "reports each market's latest populated model date" do
    Stock::AREAS.each do |area|
      StocksCoefsStav.create!(stock: "#{area}000001", area: area, date: Date.new(2026, 7, 31))
    end
    StocksCoefsStav.create!(stock: "sz000002", area: Stock::SZSTK, date: Date.new(2026, 7, 30))

    report = Stock::PreviewHealth.new.call

    assert report[:ready]
    assert_equal Date.new(2026, 7, 31), report[:markets][Stock::SZSTK][:date]
    assert_equal 1, report[:markets][Stock::SZSTK][:rows]
  end

  test "reports the preview incomplete when a market has no model rows" do
    StocksCoefsStav.where(area: Stock::BJSTK).delete_all

    report = Stock::PreviewHealth.new.call

    refute report[:ready]
    assert_equal({ ready: false, date: nil, rows: 0 }, report[:markets][Stock::BJSTK])
  end
end
