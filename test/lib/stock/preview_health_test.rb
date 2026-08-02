require "test_helper"

class StockPreviewHealthTest < ActiveSupport::TestCase
  setup do
    StocksCoefsStav.delete_all
    StockSignalSnapshot.delete_all
  end

  test "reports each market's latest populated model date" do
    Stock::AREAS.each do |area|
      StocksCoefsStav.create!(stock: "#{area}000001", area: area, date: Date.new(2026, 7, 31))
      StockSignalSnapshot.create!(stock: "#{area}000001", area: area, signal_date: Date.new(2026, 7, 31))
    end
    StocksCoefsStav.create!(stock: "sz000002", area: Stock::SZSTK, date: Date.new(2026, 7, 30))

    report = Stock::PreviewHealth.new.call

    assert report[:ready]
    assert report[:dates_aligned]
    assert_equal Date.new(2026, 7, 31), report[:date]
    assert_equal Date.new(2026, 7, 31), report[:markets][Stock::SZSTK][:date]
    assert_equal 1, report[:markets][Stock::SZSTK][:rows]
    assert_equal 1, report[:markets][Stock::SZSTK][:snapshot_rows]
  end

  test "reports the preview incomplete when signal history does not match current rows" do
    Stock::AREAS.each do |area|
      StocksCoefsStav.create!(stock: "#{area}000001", area: area, date: Date.new(2026, 7, 31))
      next if area == Stock::BJSTK

      StockSignalSnapshot.create!(stock: "#{area}000001", area: area, signal_date: Date.new(2026, 7, 31))
    end

    report = Stock::PreviewHealth.new.call

    refute report[:ready]
    assert_equal 0, report[:markets][Stock::BJSTK][:snapshot_rows]
    refute report[:markets][Stock::BJSTK][:ready]
  end

  test "reports the preview incomplete when market dates disagree" do
    Stock::AREAS.each_with_index do |area, index|
      date = Date.new(2026, 7, 31) - index
      StocksCoefsStav.create!(stock: "#{area}000001", area: area, date: date)
      StockSignalSnapshot.create!(stock: "#{area}000001", area: area, signal_date: date)
    end

    report = Stock::PreviewHealth.new.call

    refute report[:ready]
    refute report[:dates_aligned]
    assert_nil report[:date]
  end
end
