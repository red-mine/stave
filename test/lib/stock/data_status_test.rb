require "test_helper"

class DataStatusTest < ActiveSupport::TestCase
  test "accepts current coefficients and complete monthly chart coverage" do
    checker = Stock::DataStatus.allocate
    source_date = Date.new(2026, 7, 31)
    market = market_status(source_date: source_date, chart_stocks: 24)

    assert checker.healthy_market?(market)
  end

  test "rejects stale coefficients" do
    checker = Stock::DataStatus.allocate
    market = market_status(source_date: Date.new(2026, 7, 31), chart_stocks: 24)
    market[:tables]["stocks_coefs_years"][:date] = Date.new(2026, 7, 30)

    refute checker.healthy_market?(market)
  end

  test "rejects incomplete chart coverage" do
    checker = Stock::DataStatus.allocate
    market = market_status(source_date: Date.new(2026, 7, 31), chart_stocks: 23)

    refute checker.healthy_market?(market)
  end

  private

  def market_status(source_date:, chart_stocks:)
    tables = Stock::DataStatus::TABLES.to_h do |table|
      coefficient = Stock::DataStatus::COEFFICIENT_TABLES.include?(table)
      [
        table,
        {
          rows: 100,
          stocks: coefficient ? 24 : chart_stocks,
          date: coefficient ? source_date : source_date.beginning_of_month
        }
      ]
    end
    { source_date: source_date, tables: tables }
  end
end
