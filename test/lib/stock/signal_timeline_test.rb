require "test_helper"

class Stock::SignalTimelineTest < ActiveSupport::TestCase
  test "returns recent observations newest first and marks signal changes" do
    create_snapshot(Date.new(2026, 7, 29), "SAF1", "BUY5")
    create_snapshot(Date.new(2026, 7, 30), "SAF1", "BUY5")
    create_snapshot(Date.new(2026, 7, 31), "BUY5", "BUY5")
    create_snapshot(Date.new(2026, 7, 31), "SEL7", "SEL7", stock: "sz000002")

    entries = Stock::SignalTimeline.new(Stock::SZSTK, "sz000001").call

    assert_equal [Date.new(2026, 7, 31), Date.new(2026, 7, 30), Date.new(2026, 7, 29)], entries.map(&:date)
    assert_equal [true, false, false], entries.map(&:changed)
    assert_equal ["BUY5", "BUY5"], [entries.first.year_signal, entries.first.lohas_signal]
  end

  test "limits the number of returned observations" do
    12.times do |index|
      create_snapshot(Date.new(2026, 7, 1) + index, "BUY5", "BUY5")
    end

    assert_equal 10, Stock::SignalTimeline.new(Stock::SZSTK, "sz000001").call.size
  end

  private

  def create_snapshot(date, year_signal, lohas_signal, stock: "sz000001")
    StockSignalSnapshot.create!(
      stock: stock, area: Stock::SZSTK, signal_date: date, price: 10,
      year_signal: year_signal, lohas_signal: lohas_signal
    )
  end
end
