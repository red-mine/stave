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
    # The signal appears at dates[0] but is derived from that close, so the
    # fill happens at the next close rather than at the signalling price.
    assert_equal dates[1], trade.entry_date
    assert_equal dates[3], trade.exit_date
    assert_in_delta 10.1, trade.entry_price, 1e-9
    assert_equal 12.0, trade.exit_price
    assert_equal 18.81, trade.return_pct
    assert_equal 118_811.88, result.final_equity
    assert_equal 18.81, result.total_return
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
    assert_equal dates[1], trade.entry_date
    assert_equal dates[21], trade.exit_date
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
    # Both are filled at the dates[1] close: 10.0 and 21.0.
    assert_in_delta 10.0, flat_trade.entry_price, 1e-9
    assert_in_delta 21.0, doubled_trade.entry_price, 1e-9
    assert_equal 0.0, flat_trade.return_pct
    assert_equal 95.24, doubled_trade.return_pct
    assert_equal 147_619.05, result.final_equity
    assert_equal 47.62, result.total_return
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
    # entry: filled at the dates[1] close of 10.1, so 100_000 * (1 - 0.01)
    #        = 99_000 net exposure buys 99_000 / 10.1 worth of stock
    # exit: 99_000 * (12.0 / 10.1) = 117_623.76 raw, * (1 - 0.02) = 115_271.29 net
    # return_pct/total_return are rounded to 2 decimals: 15.271 -> 15.27
    assert_in_delta 10.1, trade.entry_price, 1e-9
    assert_equal 115_271.29, result.final_equity
    assert_equal 15.27, trade.return_pct
    assert_equal 15.27, result.total_return
  end

  test "a signal is filled at the next close and cannot be exited on the fill day" do
    dates = 22.times.map { |index| Date.new(2026, 1, 1) + index }
    dates.each_with_index do |date, index|
      year_signal, lohas_signal = index.zero? ? ["BUY5", "BUY5"] : ["WAT9", "WAT9"]
      snapshot(stock: "sz000001", date: date, price: 10.0, year_signal: year_signal, lohas_signal: lohas_signal)
    end

    # The signal is recorded at dates[0] and filled at dates[1]. max_hold_days: 0
    # would close the position the instant it could be evaluated, so the exit
    # lands on dates[2]: the earliest a filled position can be assessed is the
    # day after the fill.
    result = Stock::StrategySimulation.new(Stock::SZSTK, max_hold_days: 0).call

    trade = result.trades.first
    assert_equal dates[1], trade.entry_date
    assert_equal dates[2], trade.exit_date
    refute_equal trade.entry_date, trade.exit_date
  end

  test "never holds more than max_positions at once" do
    dates = 25.times.map { |index| Date.new(2026, 1, 1) + index }
    stocks = 12.times.map { |index| format("sz%06d", index + 1) }
    dates.each_with_index do |date, index|
      signals = index.zero? ? ["BUY5", "BUY5"] : ["WAT9", "WAT9"]
      stocks.each do |stock|
        snapshot(stock: stock, date: date, price: 10.0, year_signal: signals[0], lohas_signal: signals[1])
      end
    end

    result = Stock::StrategySimulation.new(
      Stock::SZSTK, max_positions: 10, max_hold_days: 20, buy_cost_rate: 0.0, sell_cost_rate: 0.0
    ).call

    # 12 stocks signal a buy on the same close, but only 10 slots exist.
    assert_equal 10, result.trades.size
    assert_equal stocks.first(10), result.trades.map(&:stock).sort
    assert_equal 100_000.0, result.final_equity
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
