require "test_helper"

class StocksControllerTest < ActionDispatch::IntegrationTest
  class FakeStave
    attr_reader :lookups

    def initialize(known: true)
      @known = known
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
      get stock_analysis_path("bad!")
    end

    assert_response :not_found
    assert_select "h1", text: "Stock not found"
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
      get stocks_by_area_path(Stock::SZSTK), params: { stock: "%" }
    end

    assert_response :bad_request
    assert_select "h1", text: "Invalid search"
  end
end
