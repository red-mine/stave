module StocksHelper
  SIGNAL_DETAILS = {
    "SAF1" => "Safe buy zone",
    "SOX2" => "Strong rise",
    "BUY5" => "Positive buy zone",
    "SEL7" => "Sell zone",
    "WAT8" => "Wait for confirmation",
    "WAT9" => "Avoid buying",
    "CHP0" => "Recovery buy zone"
  }.freeze

  def market_navigation(current_area)
    safe_join(Stock::AREAS.map do |area|
      classes = ["market-tab", ("is-active" if area == current_area)].compact
      link_to(area.upcase, stocks_by_area_path(area), class: classes, aria: { current: ("page" if area == current_area) })
    end)
  end

  def signal_badge(code)
    normalized = code.presence
    return content_tag(:span, "No signal", class: "signal-badge signal-neutral") unless normalized

    tone = case normalized
    when /\A(?:BUY|SAF|CHP)/ then "positive"
    when /\ASEL/ then "negative"
    when /\ASOX/ then "strong"
    else "neutral"
    end
    content_tag(
      :span,
      normalized,
      class: "signal-badge signal-#{tone}",
      title: SIGNAL_DETAILS.fetch(normalized, normalized)
    )
  end

  def formatted_number(value)
    value.nil? ? "—" : number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
  end
end
