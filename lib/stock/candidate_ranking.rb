module Stock
  class CandidateRanking
    SIGNAL_POINTS = {
      "BUY5" => 30,
      "BUY4" => 27,
      "CHP0" => 24,
      "SAF1" => 20
    }.freeze
    BUY_SIGNALS = SIGNAL_POINTS.keys.freeze
    A_SHARE_CODE_PATTERNS = {
      "sz" => %w[sz00____ sz30____],
      "sh" => %w[sh60____ sh68____],
      "bj" => %w[bj43____ bj83____ bj87____ bj88____ bj92____]
    }.freeze

    Candidate = Data.define(:record, :score, :confidence, :reasons, :history_state) do
      delegate :stock, :price, :date, :years, :lohas, to: :record
    end

    def initialize(area)
      @area = area
    end

    def call(limit: 6)
      market = StocksCoefsStav.where(area: @area)
      market_date = market.maximum(:date)
      return [] unless market_date

      records = market
        .where(date: market_date, years: BUY_SIGNALS, lohas: BUY_SIGNALS)
        .where(a_share_condition, *A_SHARE_CODE_PATTERNS.fetch(@area))

      candidates = records.map { |record| evaluate(record) }
        .sort_by { |candidate| [-candidate.score, candidate.stock] }
        .first(limit)

      previous_by_stock = previous_snapshots(candidates, before: market_date)
      candidates.map { |candidate| add_history_state(candidate, previous_by_stock[candidate.stock]) }
    end

    private

    def a_share_condition
      A_SHARE_CODE_PATTERNS.fetch(@area).map { "stock LIKE ?" }.join(" OR ")
    end

    def evaluate(record)
      score = SIGNAL_POINTS.fetch(record.years) + SIGNAL_POINTS.fetch(record.lohas)
      reasons = ["Both horizons are in a buy-family signal"]

      positive_trends = [record.year, record.loha].count { |trend| trend.to_f.positive? }
      score += positive_trends * 6
      reasons << "Both measured trends are rising" if positive_trends == 2

      supported_positions = [record.boll1, record.stav1, record.boll3, record.stav3].count { |position| position.to_i >= 0 }
      score += supported_positions * 4
      reasons << "Price position is supported on both horizons" if supported_positions == 4

      if record.years == record.lohas
        score += 6
        reasons << "The two horizons show the same signal"
      end

      if balanced_positive_trends?(record)
        score += 6
        reasons << "Short and long trend strength are reasonably balanced"
      end

      score = [score, 100].min
      Candidate.new(record:, score:, confidence: confidence_for(score), reasons: reasons.first(3), history_state: nil)
    end

    def add_history_state(candidate, previous)
      state = if previous.nil?
        "First recorded"
      elsif previous.year_signal.in?(BUY_SIGNALS) && previous.lohas_signal.in?(BUY_SIGNALS)
        "Still active"
      else
        "New buy signal"
      end

      Candidate.new(**candidate.to_h, history_state: state)
    end

    def previous_snapshots(candidates, before:)
      stocks = candidates.map(&:stock)
      return {} if stocks.empty?

      StockSignalSnapshot
        .where(area: @area, stock: stocks)
        .where(signal_date: ...before)
        .order(signal_date: :desc)
        .to_a
        .group_by(&:stock)
        .transform_values(&:first)
    end

    def balanced_positive_trends?(record)
      return false unless record.price.to_f.positive? && record.year.to_f.positive? && record.loha.to_f.positive?

      ratio = record.year.to_f / record.loha.to_f
      ratio.between?(0.25, 4.0)
    end

    def confidence_for(score)
      return "Strong" if score >= 85
      return "Moderate" if score >= 70

      "Cautious"
    end
  end
end
