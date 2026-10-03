require "test_helper"

class Stock::SignalNotifierTest < ActiveSupport::TestCase
  test "reports stocks whose signal family changed between the two latest dates" do
    create_snapshot(Date.new(2026, 7, 30), "SAF1", "BUY5", stock: "sz000001", price: 10)
    create_snapshot(Date.new(2026, 7, 31), "SEL7", "BUY5", stock: "sz000001", price: 9)
    create_snapshot(Date.new(2026, 7, 30), "WAT9", "WAT8", stock: "sz000002")
    create_snapshot(Date.new(2026, 7, 31), "CHP0", "BUY4", stock: "sz000002", price: 20)
    create_snapshot(Date.new(2026, 7, 30), "SAF1", "BUY5", stock: "sz000003")
    create_snapshot(Date.new(2026, 7, 31), "SAF1", "BUY5", stock: "sz000003")

    report = Stock::SignalNotifier.new(Stock::SZSTK).call

    assert_equal Date.new(2026, 7, 31), report.signal_date
    assert_equal Date.new(2026, 7, 30), report.previous_date
    assert_equal ["sz000002", "sz000001"], report.events.map(&:stock)
    assert_equal ["buy", "sell"], report.events.map(&:family)
    assert_equal ["watch", "buy"], report.events.map(&:previous_family)
    assert_equal 20, report.events.first.price
  end

  test "treats stocks without a previous snapshot as new" do
    create_snapshot(Date.new(2026, 7, 30), "SAF1", "BUY5", stock: "sz000001")
    create_snapshot(Date.new(2026, 7, 31), "CHP0", "BUY5", stock: "sz000002", price: 30)

    report = Stock::SignalNotifier.new(Stock::SZSTK).call

    event = report.events.first
    assert_equal "sz000002", event.stock
    assert_equal "buy", event.family
    assert_nil event.previous_family
  end

  test "returns an empty report when fewer than two dates exist" do
    create_snapshot(Date.new(2026, 7, 31), "SAF1", "BUY5")

    report = Stock::SignalNotifier.new(Stock::SZSTK).call

    assert_nil report.signal_date
    assert report.empty?
  end

  test "only considers the requested market" do
    create_snapshot(Date.new(2026, 7, 30), "SAF1", "BUY5", stock: "sz000001")
    create_snapshot(Date.new(2026, 7, 31), "SEL7", "SEL7", stock: "sz000001")
    create_snapshot(Date.new(2026, 7, 31), "SEL7", "SEL7", stock: "sh600000", area: Stock::SHSTK)

    report = Stock::SignalNotifier.new(Stock::SHSTK).call

    assert report.empty?
  end

  private

  def create_snapshot(date, year_signal, lohas_signal, stock: "sz000001", area: Stock::SZSTK, price: 10)
    StockSignalSnapshot.create!(
      stock: stock, area: area, signal_date: date, price: price,
      year_signal: year_signal, lohas_signal: lohas_signal
    )
  end
end
