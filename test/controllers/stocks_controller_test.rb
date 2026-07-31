require "test_helper"

class StocksControllerTest < ActionDispatch::IntegrationTest
  class FakeStave
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
  end

  test "stock analysis preserves its market query parameter" do
    areas = []

    Stock::Stave.stub(:new, ->(area, _days) { areas << area; FakeStave.new }) do
      get stock_analysis_path("600000", area: "sh")
    end

    assert_response :success
    assert_equal [Stock::SHSTK], areas
  end

  test "stock analysis defaults invalid market input to Shenzhen" do
    areas = []

    Stock::Stave.stub(:new, ->(area, _days) { areas << area; FakeStave.new }) do
      get stock_analysis_path("000001", area: "../../outside")
    end

    assert_response :success
    assert_equal [Stock::SZSTK], areas
  end
end
