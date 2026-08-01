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

    Candidate = Data.define(:record, :score, :confidence, :reasons) do
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

      records.map { |record| evaluate(record) }
        .sort_by { |candidate| [-candidate.score, candidate.stock] }
        .first(limit)
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
      Candidate.new(record:, score:, confidence: confidence_for(score), reasons: reasons.first(3))
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
