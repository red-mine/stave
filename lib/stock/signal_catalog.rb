module Stock
  module SignalCatalog
    ENTRIES = [
      { code: "SAF1", badge_action: "Buy", action: "Buy zone", tone: "positive", detail: "Safe buy zone", stave: "Between -2SD and -1SD", channel: "Lower half, still inside", stave_pos: "low", channel_pos: "lower", summary: "Depressed relative to trend without breaking below the channel." },
      { code: "SOX2", badge_action: "Hold", action: "Strong rise - hold", tone: "strong", detail: "Strong rise", stave: "+1SD to +2SD", channel: "Above upper boundary", stave_pos: "high", channel_pos: "above", summary: "Strong momentum, but already elevated; avoid chasing blindly." },
      { code: "SEL3", badge_action: "Sell", action: "Sell", tone: "negative", detail: "Sell after both upper boundaries are crossed downward", stave: "Returned below +2SD", channel: "Returned below upper boundary", stave_pos: "high", channel_pos: "upper", summary: "Price crossed downward into both the stave and channel after an overbought move." },
      { code: "BUY4", badge_action: "Buy", action: "Buy zone", tone: "positive", detail: "Buy zone without falling moving-average confirmation", stave: "Between -2SD and -1SD", channel: "Upper half, still inside", stave_pos: "low", channel_pos: "upper", summary: "A depressed stave position remains inside the channel without broad moving-average weakness." },
      { code: "BUY5", badge_action: "Buy", action: "Positive buy", tone: "positive", detail: "Positive buy zone", stave: "Trend to +1SD", channel: "Upper half, still inside", stave_pos: "upper", channel_pos: "upper", summary: "Constructive upward movement that is not yet highly extended." },
      { code: "SEL6", badge_action: "Sell", action: "Partial sell", tone: "negative", detail: "Partial sell after returning inside the channel", stave: "+1SD to +2SD", channel: "Crossed back inside", stave_pos: "high", channel_pos: "upper", summary: "Price crossed downward through the channel's upper boundary while remaining elevated in the stave." },
      { code: "SEL7", badge_action: "Sell", action: "Sell zone", tone: "negative", detail: "Sell zone", stave: "+1SD to +2SD", channel: "Upper half, inside", stave_pos: "high", channel_pos: "upper", summary: "An extended price remains in the upper sell zone after an overbought move." },
      { code: "WAT8", badge_action: "Wait", action: "Wait", tone: "neutral", detail: "Wait for confirmation", stave: "Between -2SD and -1SD", channel: "Upper half", stave_pos: "low", channel_pos: "upper", summary: "The 5-, 10-, 20-, and 40-day averages are all lower than one month ago, so wait instead of using BUY4." },
      { code: "WAT9", badge_action: "Avoid", action: "Avoid buying", tone: "negative", detail: "Avoid buying", stave: "Below -2SD", channel: "Below lower boundary", stave_pos: "deep", channel_pos: "below", summary: "Weak on both measures and at the greatest breakdown risk." },
      { code: "CHP0", badge_action: "Buy", action: "Cheap recovery", tone: "positive", detail: "Recovery buy zone", stave: "Below -2SD", channel: "Recovered into lower half", stave_pos: "deep", channel_pos: "lower", summary: "A higher-risk rebound after an unusually deep decline." }
    ].map(&:freeze).freeze

    BY_CODE = ENTRIES.index_by { |entry| entry.fetch(:code) }.freeze

    def self.fetch(code)
      BY_CODE.fetch(code)
    end
  end
end
