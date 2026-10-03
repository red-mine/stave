require "test_helper"

class Stock::FundamentalsQualityTest < ActiveSupport::TestCase
  test "passes when every enabled check with data meets its threshold" do
    record = build_record(roe: 5.22, report_date: Date.new(2026, 6, 30), revenue_yoy: 1.78, profit_yoy: -50.0)

    result = Stock::FundamentalsQuality.new(record).call

    assert_equal "pass", result.verdict
    assert result.pass?
    assert_in_delta 10.44, result.annualized_roe
    assert_equal %i[roe revenue_yoy], result.checks.map(&:name)
  end

  test "fails when an enabled check with data misses its threshold" do
    record = build_record(roe: 2.0, report_date: Date.new(2026, 6, 30), revenue_yoy: 1.78)

    result = Stock::FundamentalsQuality.new(record).call

    assert_equal "fail", result.verdict
    roe_check = result.checks.find { |check| check.name == :roe }
    assert_equal false, roe_check.met
  end

  test "reports unknown without a record" do
    result = Stock::FundamentalsQuality.new(nil).call

    assert_equal "unknown", result.verdict
    assert result.unknown?
    assert_empty result.checks
  end

  test "reports unknown when an enabled check has no data" do
    record = build_record(roe: 5.22, report_date: Date.new(2026, 6, 30), revenue_yoy: nil)

    result = Stock::FundamentalsQuality.new(record).call

    assert_equal "unknown", result.verdict
    revenue_check = result.checks.find { |check| check.name == :revenue_yoy }
    assert_nil revenue_check.met
  end

  test "annualizes ROE by report quarter" do
    cases = {
      Date.new(2026, 3, 31) => 4.0,
      Date.new(2026, 6, 30) => 2.0,
      Date.new(2026, 9, 30) => 4.0 / 3.0,
      Date.new(2025, 12, 31) => 1.0
    }

    cases.each do |date, factor|
      record = build_record(roe: 3.0, report_date: date)
      assert_in_delta 3.0 * factor, Stock::FundamentalsQuality.new(record).call.annualized_roe, 0.001
    end
  end

  test "disabled checks are not judged" do
    record = build_record(roe: nil, report_date: Date.new(2026, 6, 30), revenue_yoy: nil, profit_yoy: nil)
    thresholds = { roe: nil, revenue_yoy: nil, profit_yoy: nil }

    result = Stock::FundamentalsQuality.new(record, thresholds: thresholds).call

    assert_empty result.checks
    assert_equal "pass", result.verdict
  end

  test "honours custom thresholds" do
    record = build_record(roe: 3.0, report_date: Date.new(2026, 6, 30), revenue_yoy: -2.0)

    result = Stock::FundamentalsQuality.new(record, thresholds: { roe: 5.0, revenue_yoy: -3.0, profit_yoy: nil }).call

    assert_equal "pass", result.verdict
  end

  private

  def build_record(roe:, report_date:, revenue_yoy: nil, profit_yoy: nil)
    StockFundamental.new(
      area: Stock::SZSTK, stock: "sz000001", roe: roe, report_date: report_date,
      revenue_yoy: revenue_yoy, profit_yoy: profit_yoy
    )
  end
end
