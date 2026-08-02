require "test_helper"

class StocksHelperTest < ActionView::TestCase
  test "adds a plain action to each coded signal badge" do
    badge = signal_badge("SAF1")

    assert_dom_equal '<span class="signal-badge signal-positive" title="Safe buy zone"><span class="signal-code">SAF1</span><span class="signal-action">Buy</span></span>', badge
    assert_includes signal_badge("SEL7"), '<span class="signal-action">Sell</span>'
    assert_includes signal_badge("SOX2"), '<span class="signal-action">Hold</span>'
    assert_includes signal_badge("WAT8"), '<span class="signal-action">Wait</span>'
    assert_includes signal_badge("WAT9"), '<span class="signal-action">Avoid</span>'
  end

  test "labels recent and stale model dates without implying live prices" do
    travel_to Time.zone.local(2026, 8, 2, 12) do
      assert_equal({ label: "Recent", tone: "recent" }, data_recency(Date.new(2026, 7, 31)))
      assert_equal({ label: "Needs update", tone: "stale" }, data_recency(Date.new(2026, 7, 29)))
      assert_equal({ label: "Unavailable", tone: "unknown" }, data_recency(nil))
    end
  end

  test "shows refresh dates in the Shanghai calendar day and tolerates invalid input" do
    assert_equal Date.new(2026, 8, 2), refresh_finished_date("2026-08-01T17:30:00Z")
    assert_nil refresh_finished_date("not-a-time")
    assert_nil refresh_finished_date(nil)
  end

  test "formats completed refresh duration and tolerates incomplete status" do
    assert_equal "5m 28s", refresh_duration(
      started_at: "2026-08-02T08:47:20Z",
      finished_at: "2026-08-02T08:52:48Z"
    )
    assert_equal "9s", refresh_duration(
      started_at: "2026-08-02T08:47:20Z",
      finished_at: "2026-08-02T08:47:29Z"
    )
    assert_nil refresh_duration(started_at: nil, finished_at: nil)
  end

  test "reports the actual first and last chart dates" do
    series = [
      { name: "Price", data: [[Date.new(2026, 7, 29), 10], [Date.new(2026, 7, 31), 11]] },
      { name: "Trend", data: [["2026-07-30", 10.5]] }
    ]

    assert_equal "2026-07-29 – 2026-07-31", chart_date_range(series)
    assert_equal "Date range unavailable", chart_date_range([])
  end
end
