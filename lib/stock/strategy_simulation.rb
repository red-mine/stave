module Stock
  class StrategySimulation
    STARTING_CASH = 100_000.0
    MAX_HOLD_DAYS = 20
    MINIMUM_DATES = SignalPerformance::MINIMUM_DATES
    # ~0.03% broker commission on buys; ~0.03% commission + 0.05% PRC stamp
    # duty (levied on sells only) on sells.
    BUY_COST_RATE = 0.0003
    SELL_COST_RATE = 0.0008

    Result = Data.define(:ready, :dates, :starting_cash, :final_equity, :total_return, :max_drawdown, :trades, :equity_curve)
    Trade = Data.define(:stock, :entry_date, :exit_date, :entry_price, :exit_price, :return_pct, :reason)
    EquityPoint = Data.define(:date, :equity)
    # entry_cash is the gross cash committed before buy_cost_rate is deducted;
    # allocated_capital is the net exposure that actually tracks price moves.
    Position = Struct.new(:stock, :entry_index, :entry_date, :entry_price, :entry_cash, :allocated_capital, :last_price)

    def initialize(area, starting_cash: STARTING_CASH, max_hold_days: MAX_HOLD_DAYS,
                   buy_cost_rate: BUY_COST_RATE, sell_cost_rate: SELL_COST_RATE)
      @area = area
      @starting_cash = starting_cash.to_f
      @max_hold_days = max_hold_days
      @buy_cost_rate = buy_cost_rate
      @sell_cost_rate = sell_cost_rate
    end

    def call
      dates = StockSignalSnapshot.where(area: @area).distinct.order(:signal_date).pluck(:signal_date)
      return not_ready(dates.size) if dates.size < MINIMUM_DATES

      snapshots_by_date = StockSignalSnapshot.where(area: @area, signal_date: dates)
        .group_by(&:signal_date)
        .transform_values { |rows| rows.index_by(&:stock) }

      cash = @starting_cash
      positions = {}
      trades = []
      equity_curve = []

      dates.each_with_index do |date, index|
        today = snapshots_by_date[date] || {}

        # A position only ever appears in `positions` starting from the
        # iteration *after* it was opened (entries are added further below,
        # after this loop runs) — so a stock bought today cannot be
        # evaluated for exit today. T+1 is enforced by this ordering alone.
        positions.keys.each do |stock|
          position = positions[stock]
          snapshot = today[stock]
          position.last_price = snapshot.price if snapshot

          reason = exit_reason(snapshot, position, index)
          next unless reason

          cash += close_position!(trades, position, date, position.last_price, reason)
          positions.delete(stock)
        end

        candidates = today.reject { |stock, _| positions.key?(stock) }
          .select { |_stock, snapshot| snapshot.price.to_f.positive? && SignalFamily.classify(snapshot.year_signal, snapshot.lohas_signal) == "buy" }

        if cash.positive? && candidates.any?
          per_position = cash / candidates.size
          net_exposure = per_position * (1 - @buy_cost_rate)
          candidates.each do |stock, snapshot|
            positions[stock] = Position.new(stock, index, date, snapshot.price, per_position, net_exposure, snapshot.price)
          end
          cash = 0.0
        end

        equity = cash + positions.values.sum { |position| position.allocated_capital * (position.last_price / position.entry_price) }
        equity_curve << EquityPoint.new(date: date, equity: rounded(equity))
      end

      positions.each_value do |position|
        cash += close_position!(trades, position, dates.last, position.last_price, "end_of_data")
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

    def not_ready(dates_count)
      Result.new(
        ready: false, dates: dates_count, starting_cash: @starting_cash, final_equity: @starting_cash,
        total_return: 0.0, max_drawdown: 0.0, trades: [], equity_curve: []
      )
    end

    def exit_reason(snapshot, position, index)
      return "sell" if snapshot && SignalFamily.classify(snapshot.year_signal, snapshot.lohas_signal) == "sell"
      return "timeout" if index - position.entry_index >= @max_hold_days

      nil
    end

    def close_position!(trades, position, exit_date, exit_price, reason)
      raw_proceeds = position.allocated_capital * (exit_price / position.entry_price)
      net_proceeds = raw_proceeds * (1 - @sell_cost_rate)

      trades << Trade.new(
        stock: position.stock, entry_date: position.entry_date, exit_date: exit_date,
        entry_price: position.entry_price, exit_price: exit_price,
        return_pct: rounded((net_proceeds / position.entry_cash - 1) * 100),
        reason: reason
      )
      net_proceeds
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
