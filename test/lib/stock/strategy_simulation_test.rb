require "test_helper"

class StockStrategySimulationTest < ActiveSupport::TestCase
  def snapshot(stock:, date:, price:, year_signal:, lohas_signal:)
    StockSignalSnapshot.create!(
      stock: stock, area: Stock::SZSTK, signal_date: date, price: price,
      year_signal: year_signal, lohas_signal: lohas_signal
    )
  end

  test "closes a position on a sell signal and books the realized return" do
    dates = 22.times.map { |index| Date.new(2026, 1, 1) + index }
    dates.each_with_index do |date, index|
      year_signal, lohas_signal, price = case index
      when 0 then ["BUY5", "BUY5", 10.0]
      when 3 then ["SEL7", "SEL7", 12.0]
      else ["WAT9", "WAT9", 10.0 + index * 0.1]
      end
      snapshot(stock: "sz000001", date: date, price: price, year_signal: year_signal, lohas_signal: lohas_signal)
    end

    result = Stock::StrategySimulation.new(Stock::SZSTK, buy_cost_rate: 0.0, sell_cost_rate: 0.0).call

    assert result.ready
    assert_equal 1, result.trades.size
    trade = result.trades.first
    assert_equal "sell", trade.reason
    assert_equal dates[0], trade.entry_date
    assert_equal dates[3], trade.exit_date
    assert_equal 10.0, trade.entry_price
    assert_equal 12.0, trade.exit_price
    assert_equal 20.0, trade.return_pct
    assert_equal 120_000.0, result.final_equity
    assert_equal 20.0, result.total_return
  end

  test "force-closes a position after the max hold period without a sell signal" do
    dates = 25.times.map { |index| Date.new(2026, 1, 1) + index }
    dates.each_with_index do |date, index|
      year_signal, lohas_signal = index.zero? ? ["BUY5", "BUY5"] : ["WAT9", "WAT9"]
      snapshot(stock: "sz000001", date: date, price: 10.0 + index * 0.1, year_signal: year_signal, lohas_signal: lohas_signal)
    end

    result = Stock::StrategySimulation.new(Stock::SZSTK, max_hold_days: 20).call

    assert_equal 1, result.trades.size
    trade = result.trades.first
    assert_equal "timeout", trade.reason
    assert_equal dates[0], trade.entry_date
    assert_equal dates[20], trade.exit_date
  end

  test "splits available cash equally between same-day buy signals" do
    dates = 25.times.map { |index| Date.new(2026, 1, 1) + index }
    dates.each_with_index do |date, index|
      signals = index.zero? ? ["BUY5", "BUY5"] : ["WAT9", "WAT9"]
      snapshot(stock: "sz000001", date: date, price: 10.0, year_signal: signals[0], lohas_signal: signals[1])
      snapshot(stock: "sz000002", date: date, price: 20.0 + index * 1.0, year_signal: signals[0], lohas_signal: signals[1])
    end

    result = Stock::StrategySimulation.new(
      Stock::SZSTK, starting_cash: 100_000.0, max_hold_days: 20, buy_cost_rate: 0.0, sell_cost_rate: 0.0
    ).call

    assert_equal 100_000.0, result.equity_curve.first.equity
    assert_equal 2, result.trades.size
    flat_trade = result.trades.find { |trade| trade.stock == "sz000001" }
    doubled_trade = result.trades.find { |trade| trade.stock == "sz000002" }
    assert_equal 0.0, flat_trade.return_pct
    assert_equal 100.0, doubled_trade.return_pct
    assert_equal 150_000.0, result.final_equity
    assert_equal 50.0, result.total_return
  end

  test "no signals ever fire leaves the starting cash untouched" do
    dates = 21.times.map { |index| Date.new(2026, 1, 1) + index }
    dates.each do |date|
      snapshot(stock: "sz000001", date: date, price: 10.0, year_signal: "WAT9", lohas_signal: "WAT9")
    end

    result = Stock::StrategySimulation.new(Stock::SZSTK).call

    assert result.ready
    assert_empty result.trades
    assert_equal 100_000.0, result.final_equity
    assert_equal 0.0, result.total_return
  end

  test "buy and sell costs reduce the realized return and final equity" do
    dates = 22.times.map { |index| Date.new(2026, 1, 1) + index }
    dates.each_with_index do |date, index|
      year_signal, lohas_signal, price = case index
      when 0 then ["BUY5", "BUY5", 10.0]
      when 3 then ["SEL7", "SEL7", 12.0]
      else ["WAT9", "WAT9", 10.0 + index * 0.1]
      end
      snapshot(stock: "sz000001", date: date, price: price, year_signal: year_signal, lohas_signal: lohas_signal)
    end

    result = Stock::StrategySimulation.new(Stock::SZSTK, buy_cost_rate: 0.01, sell_cost_rate: 0.02).call

    trade = result.trades.first
    # entry: 100_000 * (1 - 0.01) = 99_000 net exposure bought at 10.0
    # exit: 99_000 * (12.0 / 10.0) = 118_800 raw, * (1 - 0.02) = 116_424 net
    # return_pct/total_return are rounded to 2 decimals: 16.424 -> 16.42
    assert_equal 116_424.0, result.final_equity
    assert_equal 16.42, trade.return_pct
    assert_equal 16.42, result.total_return
  end

  test "a position bought today can never be exited on that same day (T+1)" do
    dates = 22.times.map { |index| Date.new(2026, 1, 1) + index }
    dates.each_with_index do |date, index|
      year_signal, lohas_signal = index.zero? ? ["BUY5", "BUY5"] : ["WAT9", "WAT9"]
      snapshot(stock: "sz000001", date: date, price: 10.0, year_signal: year_signal, lohas_signal: lohas_signal)
    end

    # max_hold_days: 0 would, if same-day exits were possible, close the
    # position the instant it opens. The loop order in #call makes that
    # structurally impossible: the earliest a position can be evaluated for
    # exit is the day after it was entered.
    result = Stock::StrategySimulation.new(Stock::SZSTK, max_hold_days: 0).call

    trade = result.trades.first
    assert_equal dates[0], trade.entry_date
    assert_equal dates[1], trade.exit_date
    refute_equal trade.entry_date, trade.exit_date
  end

  test "reports not ready when there is no signal history" do
    result = Stock::StrategySimulation.new(Stock::SZSTK).call

    refute result.ready
    assert_equal 0, result.dates
  end

  test "withholds results until the same minimum date count as SignalPerformance" do
    (Stock::StrategySimulation::MINIMUM_DATES - 1).times do |index|
      snapshot(stock: "sz000001", date: Date.new(2026, 1, 1) + index, price: 10.0, year_signal: "BUY5", lohas_signal: "BUY5")
    end

    result = Stock::StrategySimulation.new(Stock::SZSTK).call

    refute result.ready
    assert_equal Stock::StrategySimulation::MINIMUM_DATES - 1, result.dates
  end
end
