require "test_helper"

class StocksHelperTest < ActionView::TestCase
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
end
