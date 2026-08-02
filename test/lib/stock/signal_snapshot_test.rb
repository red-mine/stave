require "test_helper"

class StockSignalSnapshotTest < ActiveSupport::TestCase
  test "captures latest signals without rewriting earlier history" do
    StocksCoefsStav.create!(
      stock: "sz000001", area: Stock::SZSTK, date: Date.new(2026, 7, 31), price: 12.5,
      loha: 0.03, year: 0.02, lohas: "BUY5", years: "SAF1",
      boll3: 1, stav3: 1, boll1: 0, stav1: -1
    )
    StockSignalSnapshot.create!(
      stock: "sz000001", area: Stock::SZSTK, signal_date: Date.new(2026, 7, 30), price: 11
    )

    assert_equal 1, Stock::SignalSnapshot.capture!(Stock::SZSTK)
    assert_equal 1, Stock::SignalSnapshot.capture!(Stock::SZSTK)
    assert_equal 2, StockSignalSnapshot.count

    current = StockSignalSnapshot.find_by!(signal_date: Date.new(2026, 7, 31))
    assert_equal "BUY5", current.lohas_signal
    assert_equal "SAF1", current.year_signal
    assert_equal 12.5, current.price
    assert_equal 1, current.lohas_channel
    assert_equal(-1, current.year_stave)
  end

  test "does nothing when a market has no calculated signals" do
    assert_equal 0, Stock::SignalSnapshot.capture!(Stock::BJSTK)
    assert_empty StockSignalSnapshot.all
  end

  test "does not rewrite unchanged snapshots" do
    StocksCoefsStav.create!(
      stock: "sz000001", area: Stock::SZSTK, date: Date.new(2026, 7, 31), price: 12.5,
      loha: 0.03, year: 0.02, lohas: "BUY5", years: "SAF1",
      boll3: 1, stav3: 1, boll1: 0, stav1: -1
    )

    Stock::SignalSnapshot.capture!(Stock::SZSTK)
    snapshot = StockSignalSnapshot.find_by!(stock: "sz000001")
    original_updated_at = snapshot.updated_at

    travel_to(1.hour.from_now) do
      assert_equal 1, Stock::SignalSnapshot.capture!(Stock::SZSTK)
    end

    snapshot.reload
    assert_equal original_updated_at, snapshot.updated_at
  end

  test "updates snapshots when the underlying signal changes" do
    StocksCoefsStav.create!(
      stock: "sz000001", area: Stock::SZSTK, date: Date.new(2026, 7, 31), price: 12.5,
      loha: 0.03, year: 0.02, lohas: "BUY5", years: "SAF1",
      boll3: 1, stav3: 1, boll1: 0, stav1: -1
    )

    Stock::SignalSnapshot.capture!(Stock::SZSTK)
    original_updated_at = StockSignalSnapshot.find_by!(stock: "sz000001").updated_at

    StocksCoefsStav.find_by!(stock: "sz000001").update!(price: 13.0, lohas: "CHP0")

    travel_to(1.hour.from_now) do
      assert_equal 1, Stock::SignalSnapshot.capture!(Stock::SZSTK)
    end

    snapshot = StockSignalSnapshot.find_by!(stock: "sz000001")
    assert_equal 13.0, snapshot.price
    assert_equal "CHP0", snapshot.lohas_signal
    assert_not_equal original_updated_at, snapshot.updated_at
  end
end
