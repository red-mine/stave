module Stock
  class SignalPerformance
    MINIMUM_DATES = 20
    MINIMUM_SAMPLE = 5

    Report = Data.define(:ready, :dates, :horizon, :cohorts)
    Cohort = Data.define(
      :year_signal, :lohas_signal, :sample_size, :win_rate,
      :average_return, :average_drawdown, :trend_group
    )

    def initialize(area, horizon: 5)
      @area = area
      @horizon = horizon
    end

    def call(signal_type: :buy, group_by_trend: false)
      scope = StockSignalSnapshot.where(area: @area)
      dates = scope.distinct.order(:signal_date).pluck(:signal_date)
      return Report.new(ready: false, dates: dates.size, horizon: @horizon, cohorts: []) if dates.size < MINIMUM_DATES

      date_positions = dates.each_with_index.to_h
      outcomes = Hash.new { |hash, key| hash[key] = [] }

      scope.order(:stock, :signal_date).to_a.group_by(&:stock).each_value do |snapshots|
        by_date = snapshots.index_by(&:signal_date)
        snapshots.each do |entry|
          next unless signal_match?(entry, signal_type)

          entry_position = date_positions.fetch(entry.signal_date)
          exit_date = dates[entry_position + @horizon]
          next unless exit_date

          exit_snapshot = by_date[exit_date]
          next unless valid_prices?(entry, exit_snapshot)

          path = dates[entry_position..(entry_position + @horizon)].filter_map { |date| by_date[date]&.price }
          next unless path.size == @horizon + 1

          outcome = {
            return: percentage_change(entry.price, exit_snapshot.price),
            drawdown: path.map { |price| percentage_change(entry.price, price) }.min
          }

          key = if group_by_trend
            [
              entry.year_signal,
              entry.lohas_signal,
              trend_group(entry.year_trend, entry.long_trend)
            ]
          else
            [entry.year_signal, entry.lohas_signal, nil]
          end

          outcomes[key] << outcome
        end
      end

      cohorts = outcomes.filter_map do |(year_signal, lohas_signal, trend_group), values|
        next if values.size < MINIMUM_SAMPLE

        Cohort.new(
          year_signal: year_signal,
          lohas_signal: lohas_signal,
          sample_size: values.size,
          win_rate: rounded(values.count { |value| value[:return].positive? }.fdiv(values.size) * 100),
          average_return: rounded(values.sum { |value| value[:return] }.fdiv(values.size)),
          average_drawdown: rounded(values.sum { |value| value[:drawdown] }.fdiv(values.size)),
          trend_group: trend_group
        )
      end.sort_by { |cohort| [-cohort.sample_size, cohort.year_signal.to_s, cohort.lohas_signal.to_s, cohort.trend_group.to_s] }

      Report.new(ready: true, dates: dates.size, horizon: @horizon, cohorts: cohorts)
    end

    private

    # Membership used to be spelled out here as its own BUY_SIGNALS and
    # SELL_SIGNALS lists, and the buy/sell test restated SignalFamily.classify's
    # rule. Both could drift from the family the rest of the app filters and
    # labels by, so this asks SignalFamily directly.
    def signal_match?(snapshot, signal_type)
      return true unless signal_type == :buy || signal_type == :sell

      SignalFamily.classify(snapshot.year_signal, snapshot.lohas_signal) == signal_type.to_s
    end

    def trend_group(year_trend, long_trend)
      # A third copy of the slope thresholds used to live here. The values it
      # produced were identical to Stock::Trend's: nil slopes are dropped by
      # compact before this map, so Trend.classify's "unknown" never fires.
      trends = [year_trend, long_trend].compact.map { |c| Trend.classify(c) }
      return "mixed" if trends.uniq.size > 1
      trends.first || "unknown"
    end

    def valid_prices?(entry, exit_snapshot)
      entry.price.to_f.positive? && exit_snapshot&.price.to_f.positive?
    end

    def percentage_change(start_price, end_price)
      (end_price.to_f / start_price.to_f - 1) * 100
    end

    def rounded(value)
      value.round(2)
    end
  end
end
