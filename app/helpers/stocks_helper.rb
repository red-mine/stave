module StocksHelper
  def market_navigation(current_area)
    safe_join(Stock::AREAS.map do |area|
      classes = ["market-tab", ("is-active" if area == current_area)].compact
      link_to(area.upcase, stocks_by_area_path(area), class: classes, aria: { current: ("page" if area == current_area) })
    end)
  end

  def signal_badge(code)
    normalized = code.presence
    return content_tag(:span, "No signal", class: "signal-badge signal-neutral") unless normalized

    signal = Stock::SignalCatalog::BY_CODE[normalized]
    tone = signal&.fetch(:tone, nil) || "neutral"
    content_tag(:span, class: "signal-badge signal-#{tone}", title: signal&.fetch(:detail, nil) || normalized) do
      safe_join([
        content_tag(:span, normalized, class: "signal-code"),
        content_tag(:span, signal&.fetch(:badge_action, nil) || "Signal", class: "signal-action")
      ])
    end
  end

  def linked_signal_badge(code, return_filter: nil)
    label = code.presence || "No signal"
    anchor = "signal-#{code.downcase}" if code.present?
    guide_options = { area: @area, anchor: anchor }
    guide_options[:return_signal] = return_filter if return_filter.present? && return_filter != "all"
    link_to(
      signal_badge(code),
      signal_guide_path(**guide_options),
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

  # Both of these used to keep their own copy of the slope thresholds and the
  # band labels, so the buy-candidate list on the market page and a stock's own
  # trend health could drift apart. Stock::Trend now owns both.
  def trend_status_label(status)
    Stock::Trend.label(status)
  end

  def fundamentals_verdict_label(verdict)
    {
      "pass" => "Sound fundamentals",
      "fail" => "Weak fundamentals",
      "unknown" => "Fundamentals unverified"
    }.fetch(verdict)
  end

  def fundamentals_badge(record)
    quality = Stock::FundamentalsQuality.new(record).call
    content_tag(
      :span, fundamentals_verdict_label(quality.verdict),
      class: "fundamentals-badge fundamentals-#{quality.verdict}",
      title: fundamentals_tooltip(record, quality)
    )
  end

  def signed_percentage(value)
    return "—" if value.nil?

    formatted = number_to_percentage(value.abs, precision: 1)
    value.negative? ? "-#{formatted}" : "+#{formatted}"
  end

  def market_cap_label(value)
    return "—" if value.nil?

    number_to_human(value, units: { thousand: "K", million: "M", billion: "B", trillion: "T" }, format: "%n%u")
  end

  def fundamental_check_label(check)
    name = { roe: "ROE (annualized)", revenue_yoy: "Revenue YoY", profit_yoy: "Profit YoY" }.fetch(check.name)
    return "#{name}: no data (needs ≥ #{check.threshold}%)" if check.value.nil?

    comparison = check.met ? "≥" : "<"
    "#{name}: #{signed_percentage(check.value)} #{comparison} #{check.threshold}%"
  end

  def classify_trend(coef)
    Stock::Trend.classify(coef)
  end

  private

  def fundamentals_tooltip(record, quality)
    return "No fundamentals fetched yet. Run bin/rails fundamentals_refresh." if record.nil?

    parts = quality.checks.map { |check| fundamental_check_label(check) }
    parts << "Report period: #{record.report_date}" if record.report_date
    parts << "Fetched: #{record.fetched_at.to_date}" if record.fetched_at
    parts.join(" · ")
  end
end
