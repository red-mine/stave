require "test_helper"

class StockSignalPerformanceTest < ActiveSupport::TestCase
  test "measures only forward outcomes for buy-signal cohorts" do
    dates = 20.times.map { |index| Date.new(2026, 1, 1) + index }
    5.times do |stock_index|
      dates.each_with_index do |date, date_index|
        direction = stock_index < 3 ? 1.0 : -0.5
        StockSignalSnapshot.create!(
          stock: format("sz%06d", stock_index), area: Stock::SZSTK,
          signal_date: date, price: 100 + direction * date_index,
          year_signal: "BUY5", lohas_signal: "BUY5"
        )
      end
    end
    dates.each_with_index do |date, date_index|
      StockSignalSnapshot.create!(
        stock: "sz999999", area: Stock::SZSTK, signal_date: date,
        price: 100 - date_index, year_signal: "SEL7", lohas_signal: "SEL7"
      )
    end

    report = Stock::SignalPerformance.new(Stock::SZSTK, horizon: 5).call

    assert report.ready
    assert_equal 20, report.dates
    assert_equal 1, report.cohorts.size
    cohort = report.cohorts.first
    assert_equal ["BUY5", "BUY5"], [cohort.year_signal, cohort.lohas_signal]
    assert_equal 75, cohort.sample_size
    assert_equal 60.0, cohort.win_rate
    assert_operator cohort.average_return, :>, 0
    assert_operator cohort.average_drawdown, :<, 0
  end

  test "withholds results until twenty distinct market dates exist" do
    19.times do |index|
      StockSignalSnapshot.create!(
        stock: "sz000001", area: Stock::SZSTK,
        signal_date: Date.new(2026, 1, 1) + index, price: 10 + index,
        year_signal: "BUY5", lohas_signal: "BUY5"
      )
    end

    report = Stock::SignalPerformance.new(Stock::SZSTK).call

    refute report.ready
    assert_empty report.cohorts
  end
end
