require "test_helper"

class StocksControllerTest < ActionDispatch::IntegrationTest
  class FakeStave
    attr_reader :lookups

    def initialize(known: true, stock_date: Date.new(2026, 7, 31), market_date: Date.new(2026, 7, 31))
      @known = known
      @stock_date = stock_date
      @market_date = market_date
      @lookups = []
    end

    def known_stock?(stock)
      @lookups << stock
      @known
    end

    def good_index(_stock)
      [[], nil]
    end

    def strongest_buy_candidates(limit: 6)
      []
    end

    def good_show(_stock)
      [[], [], [], []]
    end

    def data_dates(_stock)
      [@stock_date, @market_date]
    end
  end

  test "market page uses the market from the route" do
    areas = []

    Stock::Stave.stub(:new, ->(area, _days) { areas << area; FakeStave.new }) do
      get stocks_by_area_path("sh")
    end

    assert_response :success
    assert_equal [Stock::SHSTK], areas
    assert_select ".app-shell"
    assert_select "a[href='#{stocks_by_area_path(Stock::BJSTK)}']", text: "BJ"
    assert_select "#stock-search-help", text: /full code or a partial symbol/
    assert_select "input#stock[inputmode='search'][enterkeyhint='search'][autocapitalize='none'][aria-describedby='stock-search-help']"
  end

  test "market page displays the last successful daily refresh" do
    status = {
      state: "succeeded",
      source: "scheduled",
      started_at: "2026-08-01T17:29:51Z",
      finished_at: "2026-08-01T17:30:00Z"
    }

    Stock::RefreshRun.stub(:new, -> { Struct.new(:status).new(status) }) do
      get stocks_by_area_path("sz")
    end

    assert_response :success
    assert_select ".refresh-status", text: /Scheduled refresh verified 2026-08-02 in 9s/
  end

  test "market page discloses automatic stale-lock recovery" do
    status = {
      state: "succeeded", source: "scheduled", recovered_stale_lock: true,
      started_at: "2026-08-01T17:29:51Z", finished_at: "2026-08-01T17:30:00Z"
    }

    Stock::RefreshRun.stub(:new, -> { Struct.new(:status).new(status) }) do
      get stocks_by_area_path("sz")
    end

    assert_response :success
    assert_select ".refresh-status", text: /after recovering an expired lock/
  end

  test "market page displays an installed automatic refresh schedule" do
    schedule = { enabled: true, time: "20:30" }

    Stock::RefreshSchedule.stub(:new, -> { Struct.new(:status).new(schedule) }) do
      get stocks_by_area_path("sz")
    end

    assert_response :success
    assert_select ".refresh-schedule", text: /Automatic refresh daily at 20:30/
  end

  test "stock analysis preserves its market query parameter" do
    areas = []

    Stock::Stave.stub(:new, ->(area, _days) { areas << area; FakeStave.new }) do
      get stock_analysis_path("600000", area: "sh")
    end

    assert_response :success
    assert_equal [Stock::SHSTK], areas
    assert_select ".chart-card", count: 4
  end

  test "stock analysis labels charts with their actual date range" do
    stave = FakeStave.new
    long_series = [{ name: "Price", data: [[Date.new(2023, 1, 3), 10], [Date.new(2026, 7, 31), 12]] }]
    year_series = [{ name: "Price", data: [[Date.new(2025, 8, 1), 11], [Date.new(2026, 7, 31), 12]] }]
    stave.define_singleton_method(:good_show) { |_stock| [long_series, year_series, long_series, year_series] }

    Stock::Stave.stub(:new, ->(*) { stave }) do
      get stock_analysis_path("000522", area: Stock::SZSTK)
    end

    assert_response :success
    assert_select ".chart-sampling-note", text: /one point per month.*one point per quarter.*authoritative final trading date/m
    assert_select ".chart-period", count: 2, text: /3\.5 years.*2023-01-03.*2026-07-31/m
    assert_select ".chart-period", count: 2, text: /quarterly/
    assert_select ".chart-period", count: 2, text: /1 year.*2025-08-01.*2026-07-31/m
    assert_select ".chart-period", count: 2, text: /monthly/
  end

  test "stock analysis accepts a market-prefixed identifier" do
    calls = []
    stave = FakeStave.new

    Stock::Stave.stub(:new, ->(area, _days) { calls << area; stave }) do
      get stock_analysis_path("SH600000", area: Stock::SZSTK)
    end

    assert_response :success
    assert_equal [Stock::SHSTK], calls
    assert_equal ["sh600000"], stave.lookups
    assert_select "h1", text: "SH600000"
    assert_select "a[href='#{stocks_by_area_path(Stock::SHSTK)}']", text: /Back to SH signals/
  end

  test "stock analysis adds the selected market to an unprefixed identifier" do
    stave = FakeStave.new

    Stock::Stave.stub(:new, ->(*) { stave }) do
      get stock_analysis_path("600000", area: Stock::SHSTK)
    end

    assert_response :success
    assert_equal ["sh600000"], stave.lookups
    assert_select "h1", text: "SH600000"
  end

  test "stock analysis identifies historical data using the stock's own date" do
    stave = FakeStave.new(
      stock_date: Date.new(2013, 3, 13),
      market_date: Date.new(2026, 7, 31)
    )

    Stock::Stave.stub(:new, ->(*) { stave }) do
      get stock_analysis_path("000522", area: Stock::SZSTK)
    end

    assert_response :success
    assert_select ".data-freshness.is-historical", text: /2013-03-13/
    assert_select ".data-freshness", text: /SZ market data continues through 2026-07-31/
  end

  test "stock analysis shows recorded signal history without reconstructing missing history" do
    StockSignalSnapshot.create!(
      stock: "sz000522", area: Stock::SZSTK, signal_date: Date.new(2026, 7, 30),
      price: 10.5, year_signal: "SAF1", lohas_signal: "BUY5"
    )
    StockSignalSnapshot.create!(
      stock: "sz000522", area: Stock::SZSTK, signal_date: Date.new(2026, 7, 31),
      price: 10.8, year_signal: "BUY5", lohas_signal: "BUY5"
    )

    Stock::Stave.stub(:new, ->(*) { FakeStave.new }) do
      get stock_analysis_path("000522", area: Stock::SZSTK)
    end

    assert_response :success
    assert_select ".signal-timeline", count: 1
    assert_select ".current-decision.decision-buy", count: 1, text: /Buy agreement.*2026-07-31.*10.8/m
    assert_select ".decision-signals", text: /Year.*BUY5.*LOHAS.*BUY5/m
    assert_select ".decision-reason", text: /Both recorded horizons.*not personalized financial advice/
    assert_select "a.decision-guide[href='#{signal_guide_path(area: Stock::SZSTK)}']", text: /Understand these signals/
    assert_select ".timeline-entry", count: 2
    assert_select ".timeline-entry.is-change", count: 1, text: /2026-07-31.*BUY5.*10.8/m
    assert_select "a[href='#{signal_history_path(area: Stock::SZSTK)}']", text: /All market history/
  end

  test "stock analysis defaults invalid market input to Shenzhen" do
    areas = []

    Stock::Stave.stub(:new, ->(area, _days) { areas << area; FakeStave.new }) do
      get stock_analysis_path("000001", area: "../../outside")
    end

    assert_response :success
    assert_equal [Stock::SZSTK], areas
  end

  test "rejects malformed stock identifiers" do
    Stock::Stave.stub(:new, ->(*) { flunk "engine should not be initialized" }) do
      get stock_analysis_path("bad!", area: Stock::BJSTK)
    end

    assert_response :not_found
    assert_select "h1", text: "Stock not found"
    assert_select "a[href='#{stocks_by_area_path(Stock::BJSTK)}']", text: "Return to market signals"
  end

  test "rejects alphabetic stock identifiers" do
    Stock::Stave.stub(:new, ->(*) { flunk "engine should not be initialized" }) do
      get stock_analysis_path("shabcdef")
    end

    assert_response :not_found
  end

  test "returns not found when a stock is absent from the selected market" do
    Stock::Stave.stub(:new, ->(*) { FakeStave.new(known: false) }) do
      get stock_analysis_path("600000", area: Stock::SHSTK)
    end

    assert_response :not_found
  end

  test "rejects malformed stock searches" do
    Stock::Stave.stub(:new, ->(*) { flunk "engine should not be initialized" }) do
      get stocks_by_area_path(Stock::SHSTK), params: { stock: "%" }
    end

    assert_response :bad_request
    assert_select "h1", text: "Invalid search"
    assert_select "a[href='#{stocks_by_area_path(Stock::SHSTK)}']", text: "Return to market signals"
  end

  test "market signals are available as JSON" do
    signal = StocksCoefsStav.create!(
      stock: "sh600000",
      area: Stock::SHSTK,
      loha: 1.2,
      year: 0.8,
      price: 12.34,
      lohas: "BUY5",
      date: Date.new(2026, 7, 31)
    )

    get stocks_by_area_path(Stock::SHSTK, format: :json)

    assert_response :success
    payload = response.parsed_body
    assert_equal ["sh600000"], payload.pluck("stock")
    assert_equal signal.price, payload.first.fetch("price")
    assert_equal stock_analysis_url("sh600000", area: Stock::SHSTK, format: :json), payload.first.fetch("url")
  end

  test "market page labels stocks whose data ended before the market date" do
    StocksCoefsStav.create!(
      stock: "sz000522", area: Stock::SZSTK, price: 10,
      lohas: "BUY5", date: Date.new(2013, 3, 13)
    )
    StocksCoefsStav.create!(
      stock: "sz000001", area: Stock::SZSTK, price: 11,
      lohas: "BUY5", date: Date.new(2026, 7, 31)
    )

    get stocks_by_area_path(Stock::SZSTK)

    assert_response :success
    assert_equal ["Stock", "Year signal", "LOHAS signal"], css_select(".stock-table th").first(3).map { |header| header.text.strip }
    assert_select ".stock-table th.metric-column", count: 7
    assert_select ".stock-table tbody tr:first-child td.metric-column", count: 7
    assert_select ".mobile-table-note", text: /Tap a stock for price, trend, channel, and chart details/
    assert_select ".stock-code a[aria-label='Open SZ000001 analysis'] .stock-open-arrow", text: "→"
    guide_path = signal_guide_path(area: Stock::SZSTK)
    assert_select "a.guide-link[href='#{guide_path}']", text: /Open signal guide/
    assert_select "a.signal-guide-link[href='#{guide_path}']", count: 4
    assert_select "tr.is-historical", count: 1 do
      assert_select ".stock-code", text: /SZ000522/
      assert_select ".historical-label", text: "Historical"
      assert_select ".historical-date", text: "Ended 2013-03-13"
    end
    assert_select "tr:not(.is-historical) .stock-code", text: /SZ000001/
  end

  test "market page ranks current buy-family candidates" do
    StocksCoefsStav.create!(
      stock: "sz002653", area: Stock::SZSTK, price: 62.38,
      years: "BUY5", lohas: "BUY5", date: Date.new(2026, 7, 31)
    )
    StocksCoefsStav.create!(
      stock: "sz000001", area: Stock::SZSTK, price: 11,
      years: "SAF1", lohas: "BUY5", date: Date.new(2026, 7, 31)
    )
    StocksCoefsStav.create!(
      stock: "sz000002", area: Stock::SZSTK, price: 10,
      years: "BUY5", lohas: "BUY5", date: Date.new(2026, 7, 30)
    )
    StocksCoefsStav.create!(
      stock: "sz880016", area: Stock::SZSTK, price: 89,
      years: "BUY5", lohas: "BUY5", date: Date.new(2026, 7, 31)
    )

    get stocks_by_area_path(Stock::SZSTK)

    assert_response :success
    assert_select ".buy-panel", count: 1
    assert_select ".buy-card", count: 1, text: /SZ002653/
    assert_select ".buy-card", text: /BUY5 \+ BUY5/
    assert_select ".candidate-history", text: /First recorded/
    assert_select ".candidate-score", text: %r{/100}
    assert_select ".candidate-score", text: /agreement/
    assert_select ".candidate-details", count: 2, text: /Why this score?/
    assert_select ".candidate-mobile-reasons", count: 2, text: /Why this score.*Both horizons are in a buy-family signal/m
    assert_select "article.buy-card", count: 2
    assert_select ".candidate-details a", count: 0
    assert_select "a.candidate-open[href='#{stock_analysis_path("sz002653", area: Stock::SZSTK)}']", text: /Open analysis/
    assert_select ".data-status-recent", text: "Recent"
    assert_select "a.history-shortcut[href='#{signal_history_path(area: Stock::SZSTK)}']", text: /View signal history/
    assert_select ".risk-note", text: /not a guarantee/
  end

  test "search results hide the market-wide buy shortlist" do
    get stocks_by_area_path(Stock::SZSTK), params: { stock: "002653" }

    assert_response :success
    assert_select ".buy-panel", count: 0
  end

  test "market action filters use conservative signal groups" do
    {
      "sz000001" => ["BUY5", "SAF1"],
      "sz000002" => ["BUY5", "SEL7"],
      "sz000003" => ["WAT9", "BUY5"]
    }.each do |stock, (years, lohas)|
      StocksCoefsStav.create!(
        stock: stock, area: Stock::SZSTK, price: 10,
        years: years, lohas: lohas, date: Date.new(2026, 7, 31)
      )
    end

    get stocks_by_area_path(Stock::SZSTK), params: { signal: "buy" }
    assert_response :success
    assert_select ".stock-code", count: 1, text: /SZ000001/
    assert_select ".signal-filter.is-active", text: /Buy agreement.*1/m
    assert_select ".signal-filter", count: 4
    assert_select ".signal-filter", text: /All.*3/m

    get stocks_by_area_path(Stock::SZSTK), params: { signal: "sell" }
    assert_select ".stock-code", count: 1, text: /SZ000002/

    get stocks_by_area_path(Stock::SZSTK), params: { signal: "watch" }
    assert_select ".stock-code", count: 1, text: /SZ000003/
  end

  test "invalid action filters safely default to all" do
    get stocks_by_area_path(Stock::SZSTK), params: { signal: "unknown" }

    assert_response :success
    assert_select ".signal-filter.is-active", text: /All.*0/m
  end

  test "stock analysis is available as JSON" do
    stave = FakeStave.new

    Stock::Stave.stub(:new, ->(*) { stave }) do
      get stock_analysis_path("600000", area: Stock::SHSTK, format: :json)
    end

    assert_response :success
    payload = response.parsed_body
    assert_equal "sh600000", payload.fetch("stock")
    assert_equal Stock::SHSTK, payload.fetch("area")
    assert_equal "2026-07-31", payload.fetch("data_date")
    assert_equal "2026-07-31", payload.fetch("market_date")
    assert_equal false, payload.fetch("historical")
    assert_nil payload.fetch("decision")
    assert_nil payload.fetch("latest_signal")
    assert_equal [], payload.fetch("signal_history")
    assert_equal %w[bolls_lohas bolls_years stave_lohas stave_years], payload.fetch("charts").keys.sort
  end

  test "stock analysis JSON includes the shared decision and recorded timeline" do
    StockSignalSnapshot.create!(
      stock: "sh600000", area: Stock::SHSTK, signal_date: Date.new(2026, 7, 30),
      price: 10.0, year_signal: "WAT9", lohas_signal: "BUY5"
    )
    StockSignalSnapshot.create!(
      stock: "sh600000", area: Stock::SHSTK, signal_date: Date.new(2026, 7, 31),
      price: 10.5, year_signal: "BUY5", lohas_signal: "SAF1"
    )

    Stock::Stave.stub(:new, ->(*) { FakeStave.new }) do
      get stock_analysis_path("600000", area: Stock::SHSTK, format: :json)
    end

    assert_response :success
    payload = response.parsed_body
    assert_equal "buy", payload.fetch("decision")
    assert_equal "2026-07-31", payload.dig("latest_signal", "date")
    assert_equal "BUY5", payload.dig("latest_signal", "year_signal")
    assert_equal 2, payload.fetch("signal_history").size
    assert_equal true, payload.fetch("signal_history").first.fetch("changed")
  end

  test "signal guide explains every active signal on a mobile-friendly page" do
    get signal_guide_path(area: Stock::SHSTK)

    assert_response :success
    assert_select "h1", text: "Signal guide"
    assert_select ".guide-card", count: 10
    assert_select "a[href='/stave/stave.png?v=4']", text: /restored original illustrated guide/
    assert_select ".example-item", count: 10
    assert_select ".example-item", text: /Buy while the channel holds/
    assert_select ".legacy-code", count: 0
    %w[SAF1 SOX2 SEL3 BUY4 BUY5 SEL6 SEL7 WAT8 WAT9 CHP0].each do |code|
      assert_select ".guide-card", text: /#{code}/
    end
    assert_select "a[href='#{stocks_by_area_path(Stock::SHSTK)}']", text: /Back to SH signals/
  end

  test "signal history reports evidence coverage without premature performance claims" do
    2.times do |index|
      StockSignalSnapshot.create!(
        stock: "sz00000#{index}", area: Stock::SZSTK,
        signal_date: Date.new(2026, 7, 31), price: 10 + index
      )
    end

    get signal_history_path(area: Stock::SZSTK)

    assert_response :success
    assert_select "h1", text: "Signal history"
    assert_select ".history-card", count: 3
    assert_select ".history-card", text: /SZ.*Trading dates.*1.*Snapshot rows.*2/m
    assert_select ".history-state.is-collecting", count: 3
    assert_select ".performance-panel", count: 0
    assert_select ".history-note", text: /sample size, average return, win rate, and drawdown/
    assert_select "a[href='#{stocks_by_area_path(Stock::SZSTK)}']", text: /Back to SZ signals/
  end

  test "signal history displays qualified forward performance with warnings" do
    cohort = Stock::SignalPerformance::Cohort.new(
      year_signal: "BUY5", lohas_signal: "BUY5", sample_size: 75,
      win_rate: 60.0, average_return: 1.2, average_drawdown: -2.1
    )
    report = Stock::SignalPerformance::Report.new(ready: true, dates: 20, horizon: 5, cohorts: [cohort])

    Stock::SignalPerformance.stub(:new, ->(*) { Struct.new(:call).new(report) }) do
      get signal_history_path(area: Stock::SZSTK)
    end

    assert_response :success
    assert_select ".performance-panel", count: 1
    assert_select ".performance-card", text: /BUY5 \+ BUY5.*75.*60.0%.*1.2%.*-2.1%/m
    assert_select ".performance-warning", text: /not a forecast.*transaction costs are not yet deducted/
  end

  test "JSON errors use a structured response" do
    Stock::Stave.stub(:new, ->(*) { flunk "engine should not be initialized" }) do
      get stock_analysis_path("bad!", format: :json)

      assert_response :not_found
      assert_equal({ "error" => "Stock not found" }, response.parsed_body)

      get stocks_by_area_path(Stock::SZSTK, format: :json), params: { stock: "%" }
    end

    assert_response :bad_request
    assert_equal({ "error" => "Invalid stock search" }, response.parsed_body)
  end
end
