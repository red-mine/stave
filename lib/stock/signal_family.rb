module Stock
  module SignalFamily
    BUY = %w[SAF1 BUY4 BUY5 CHP0].freeze
    SELL = %w[SEL3 SEL6 SEL7].freeze

    module_function

    def classify(year_signal, lohas_signal)
      signals = [year_signal, lohas_signal]
      return "sell" if signals.any? { |signal| signal.in?(SELL) }
      return "buy" if signals.all? { |signal| signal.in?(BUY) }

      "watch"
    end

    def label(family)
      { "buy" => "Buy agreement", "sell" => "Sell alert", "watch" => "Watch" }.fetch(family)
    end

    def explanation(family)
      {
        "buy" => "Both recorded horizons are in the buy family.",
        "sell" => "At least one recorded horizon is in the sell family.",
        "watch" => "There is no two-horizon buy agreement and no sell alert."
      }.fetch(family)
    end
  end
end
