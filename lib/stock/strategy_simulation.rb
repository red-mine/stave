module Stock
  class StrategySimulation
    STARTING_CASH = 100_000.0
    MAX_HOLD_DAYS = 20

    Result = Data.define(:ready, :dates, :starting_cash, :final_equity, :total_return, :max_drawdown, :trades, :equity_curve)
    Trade = Data.define(:stock, :entry_date, :exit_date, :entry_price, :exit_price, :return_pct, :reason)
    EquityPoint = Data.define(:date, :equity)
    Position = Struct.new(:stock, :entry_index, :entry_date, :entry_price, :allocated_capital, :last_price)

    def initialize(area, starting_cash: STARTING_CASH, max_hold_days: MAX_HOLD_DAYS)
      @area = area
      @starting_cash = starting_cash.to_f
      @max_hold_days = max_hold_days
    end

    def call
      dates = StockSignalSnapshot.where(area: @area).distinct.order(:signal_date).pluck(:signal_date)
      return not_ready if dates.empty?

      snapshots_by_date = StockSignalSnapshot.where(area: @area, signal_date: dates)
        .group_by(&:signal_date)
        .transform_values { |rows| rows.index_by(&:stock) }

      cash = @starting_cash
      positions = {}
      trades = []
      equity_curve = []

      dates.each_with_index do |date, index|
        today = snapshots_by_date[date] || {}

        positions.keys.each do |stock|
          position = positions[stock]
          snapshot = today[stock]
          position.last_price = snapshot.price if snapshot

          reason = exit_reason(snapshot, position, index)
          next unless reason

          trades << close_position(position, date, position.last_price, reason)
          cash += position.allocated_capital * (position.last_price / position.entry_price)
          positions.delete(stock)
        end

        candidates = today.reject { |stock, _| positions.key?(stock) }
          .select { |_stock, snapshot| snapshot.price.to_f.positive? && SignalFamily.classify(snapshot.year_signal, snapshot.lohas_signal) == "buy" }

        if cash.positive? && candidates.any?
          per_position = cash / candidates.size
          candidates.each do |stock, snapshot|
            positions[stock] = Position.new(stock, index, date, snapshot.price, per_position, snapshot.price)
          end
          cash = 0.0
        end

        equity = cash + positions.values.sum { |position| position.allocated_capital * (position.last_price / position.entry_price) }
        equity_curve << EquityPoint.new(date: date, equity: rounded(equity))
      end

      positions.each_value do |position|
        trades << close_position(position, dates.last, position.last_price, "end_of_data")
        cash += position.allocated_capital * (position.last_price / position.entry_price)
      end

      Result.new(
        ready: true,
        dates: dates.size,
        starting_cash: @starting_cash,
        final_equity: rounded(cash),
        total_return: rounded((cash / @starting_cash - 1) * 100),
        max_drawdown: rounded(max_drawdown(equity_curve)),
        trades: trades,
        equity_curve: equity_curve
      )
    end

    private

    def not_ready
      Result.new(
        ready: false, dates: 0, starting_cash: @starting_cash, final_equity: @starting_cash,
        total_return: 0.0, max_drawdown: 0.0, trades: [], equity_curve: []
      )
    end

    def exit_reason(snapshot, position, index)
      return "sell" if snapshot && SignalFamily.classify(snapshot.year_signal, snapshot.lohas_signal) == "sell"
      return "timeout" if index - position.entry_index >= @max_hold_days

      nil
    end

    def close_position(position, exit_date, exit_price, reason)
      Trade.new(
        stock: position.stock, entry_date: position.entry_date, exit_date: exit_date,
        entry_price: position.entry_price, exit_price: exit_price,
        return_pct: rounded((exit_price / position.entry_price - 1) * 100),
        reason: reason
      )
    end

    def max_drawdown(equity_curve)
      peak = -Float::INFINITY
      worst = 0.0
      equity_curve.each do |point|
        peak = point.equity if point.equity > peak
        drawdown = (point.equity - peak).fdiv(peak) * 100
        worst = drawdown if drawdown < worst
      end
      worst
    end

    def rounded(value)
      value.round(2)
    end
  end
end
