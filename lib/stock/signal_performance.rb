module Stock
  class SignalPerformance
    MINIMUM_DATES = 20
    MINIMUM_SAMPLE = 5
    BUY_SIGNALS = %w[SAF1 BUY4 BUY5 CHP0].freeze
    SELL_SIGNALS = %w[SEL3 SEL6 SEL7].freeze

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
      end.sort_by { |cohort| [-cohort.sample_size, cohort.year_signal, cohort.lohas_signal, cohort.trend_group.to_s] }

      Report.new(ready: true, dates: dates.size, horizon: @horizon, cohorts: cohorts)
    end

    private

    def signal_match?(snapshot, signal_type)
      case signal_type
      when :buy then snapshot.year_signal.in?(BUY_SIGNALS) && snapshot.lohas_signal.in?(BUY_SIGNALS)
      when :sell then snapshot.year_signal.in?(SELL_SIGNALS) || snapshot.lohas_signal.in?(SELL_SIGNALS)
      else true
      end
    end

    def trend_group(year_trend, long_trend)
      trends = [year_trend, long_trend].compact.map { |c| classify_slope(c) }
      return "mixed" if trends.uniq.size > 1
      trends.first || "unknown"
    end

    def classify_slope(coef)
      return nil if coef.nil?

      c = coef.to_f
      return "strong_uptrend" if c >= 0.05
      return "uptrend" if c >= 0.02
      return "weak_uptrend" if c > 0.01
      return "flat" if c >= -0.01
      "downtrend"
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
