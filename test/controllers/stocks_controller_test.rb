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
    assert_equal %w[bolls_lohas bolls_years stave_lohas stave_years], payload.fetch("charts").keys.sort
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
