module Stock
  # Screens a StockFundamental record against the strategy's stated
  # precondition: the five-line method only applies to fundamentally sound
  # companies, because mean reversion is assumed to fail otherwise.
  #
  # Thresholds come from the environment so checks can be tuned or disabled
  # (empty string) without re-fetching data:
  #
  #   FUND_ROE_MIN            default "8"    annualized weighted ROE, percent
  #   FUND_REVENUE_YOY_MIN    default "0"    revenue YoY, percent
  #   FUND_PROFIT_YOY_MIN     default ""     net-profit YoY, percent (disabled)
  #
  # Verdicts: "pass" (every enabled check with data meets its threshold),
  # "fail" (an enabled check with data misses), "unknown" (no record, or an
  # enabled check has no data to judge).
  class FundamentalsQuality
    Result = Data.define(:verdict, :annualized_roe, :checks) do
      def pass? = verdict == "pass"

      def unknown? = verdict == "unknown"
    end

    Check = Data.define(:name, :value, :threshold, :met)

    def self.thresholds
      {
        roe: parse_threshold("FUND_ROE_MIN", "8"),
        revenue_yoy: parse_threshold("FUND_REVENUE_YOY_MIN", "0"),
        profit_yoy: parse_threshold("FUND_PROFIT_YOY_MIN", nil)
      }
    end

    def self.parse_threshold(name, default)
      raw = ENV.fetch(name, default)
      return nil if raw.nil? || raw.empty?

      Float(raw, exception: false)
    end
    private_class_method :parse_threshold

    def initialize(record, thresholds: self.class.thresholds)
      @record = record
      @thresholds = thresholds
    end

    def call
      return Result.new(verdict: "unknown", annualized_roe: nil, checks: []) unless @record

      roe = annualized_roe
      judged = []
      checks = []
      missing = false

      check(:roe, roe, judged, checks) { |value, limit| value >= limit }
      check(:revenue_yoy, @record.revenue_yoy, judged, checks) { |value, limit| value >= limit }
      check(:profit_yoy, @record.profit_yoy, judged, checks) { |value, limit| value >= limit }

      verdict = if checks.size != judged.size
        "unknown"
      elsif judged.all? { |met| met }
        "pass"
      else
        "fail"
      end

      Result.new(verdict: verdict, annualized_roe: roe, checks: checks)
    end

    private

    # Eastmoney reports cumulative weighted ROE per report period, so a
    # half-year ROE of 5% annualizes to roughly 10%. Without this scaling a
    # flat threshold would punish mid-year reports and reward year-ends.
    def annualized_roe
      return nil unless @record.roe && @record.report_date

      factor = case @record.report_date.month
      when 3 then 4.0
      when 6 then 2.0
      when 9 then 4.0 / 3.0
      else 1.0
      end
      @record.roe * factor
    end

    def check(name, value, judged, checks)
      limit = @thresholds[name]
      return unless limit

      if value.nil?
        checks << Check.new(name: name, value: nil, threshold: limit, met: nil)
      else
        met = yield(value, limit)
        checks << Check.new(name: name, value: value, threshold: limit, met: met)
        judged << met
      end
    end
  end
end
