module Stock
  module Trend
    LABELS = {
      "strong_uptrend" => "Strong uptrend",
      "uptrend" => "Uptrend",
      "weak_uptrend" => "Weak uptrend",
      "flat" => "Flat",
      "downtrend" => "Downtrend",
      "unknown" => "Unknown"
    }.freeze

    module_function

    # Turns a regression slope into a band. This was once implemented twice --
    # once for the index page's buy candidates and once for a stock's own trend
    # health -- and the two copies could disagree about what "uptrend" means.
    # The edges below differ by a single character (> versus >=), so each one
    # is pinned by test/lib/stock/trend_test.rb.
    def classify(coef)
      return "unknown" if coef.nil?

      c = coef.to_f
      return "strong_uptrend" if c >= 0.05
      return "uptrend" if c >= 0.02
      return "weak_uptrend" if c > 0.01
      return "flat" if c >= -0.01
      "downtrend"
    end

    def label(status)
      LABELS.fetch(status.to_s, status.to_s.humanize)
    end
  end
end
