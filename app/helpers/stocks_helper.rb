module StocksHelper
  SIGNAL_DETAILS = {
    "SAF1" => "Safe buy zone",
    "SOX2" => "Strong rise",
    "SEL3" => "Sell after both upper boundaries are crossed downward",
    "BUY4" => "Buy zone without falling moving-average confirmation",
    "BUY5" => "Positive buy zone",
    "SEL6" => "Partial sell after returning inside the channel",
    "SEL7" => "Sell zone",
    "WAT8" => "Wait for confirmation",
    "WAT9" => "Avoid buying",
    "CHP0" => "Recovery buy zone"
  }.freeze

  SIGNAL_ACTIONS = {
    "SAF1" => "Buy",
    "SOX2" => "Hold",
    "SEL3" => "Sell",
    "BUY4" => "Buy",
    "BUY5" => "Buy",
    "SEL6" => "Sell",
    "SEL7" => "Sell",
    "WAT8" => "Wait",
    "WAT9" => "Avoid",
    "CHP0" => "Buy"
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
    content_tag(:span, class: "signal-badge signal-#{tone}", title: SIGNAL_DETAILS.fetch(normalized, normalized)) do
      safe_join([
        content_tag(:span, normalized, class: "signal-code"),
        content_tag(:span, SIGNAL_ACTIONS.fetch(normalized, "Signal"), class: "signal-action")
      ])
    end
  end

  def linked_signal_badge(code)
    label = code.presence || "No signal"
    link_to(
      signal_badge(code),
      signal_guide_path(area: @area),
      class: "signal-guide-link",
      aria: { label: "Open signal guide for #{label}" }
    )
  end

  def formatted_number(value)
    value.nil? ? "—" : number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
  end

  def chart_date_range(series)
    dates = Array(series).flat_map { |item| Array(item[:data]) }.filter_map do |point|
      Date.parse(point.first.to_s) if point.respond_to?(:first) && point.first.present?
    rescue Date::Error
      nil
    end
    return "Date range unavailable" if dates.empty?

    "#{dates.min.iso8601} – #{dates.max.iso8601}"
  end

  def data_recency(date)
    return { label: "Unavailable", tone: "unknown" } unless date

    age = (Date.current - date).to_i
    return { label: "Recent", tone: "recent" } if age <= 3

    { label: "Needs update", tone: "stale" }
  end

  def refresh_finished_date(value)
    Time.iso8601(value).in_time_zone("Asia/Shanghai").to_date
  rescue ArgumentError, TypeError
    nil
  end

  def refresh_duration(status)
    started_at = Time.iso8601(status[:started_at])
    finished_at = Time.iso8601(status[:finished_at])
    seconds = [(finished_at - started_at).round, 0].max
    minutes, remaining_seconds = seconds.divmod(60)
    minutes.positive? ? "#{minutes}m #{remaining_seconds}s" : "#{remaining_seconds}s"
  rescue ArgumentError, TypeError
    nil
  end
end
