require "test_helper"

class StockSignalTest < ActiveSupport::TestCase
  setup do
    @engine = Stock::Stock.new(Stock::SZSTK, Stock::STAVE)
    @bands = {
      boll: 100, mup: 115, mdn: 85,
      trend: 100, up1: 110, dn1: 90, up2: 120, dn2: 80
    }
  end

  test "classifies the position-only signals" do
    assert_signal "SAF1", 87
    assert_signal "SOX2", 117
    assert_signal "BUY5", 105
    assert_signal "SEL7", 112
    assert_signal "BUY4", 85, boll: 70, mup: 100
    assert_signal "WAT9", 75
  end

  test "distinguishes BUY4 from WAT8 using falling moving averages" do
    assert_signal "BUY4", 85, boll: 70, mup: 100
    assert_signal "WAT8", 85, boll: 70, mup: 100, falling_averages: true
  end

  test "distinguishes the three sell signals using downward crossings" do
    assert_signal "SEL3", 112, previous: previous(price: 125, up2: 120, mup: 115)
    assert_signal "SEL6", 112, previous: previous(price: 118, up2: 120, mup: 115)
    assert_signal "SEL7", 112, previous: previous(price: 121, up2: 120, mup: 125)
  end

  test "classifies CHP0 after price recovers inside the lower channel" do
    assert_signal "CHP0", 75, mdn: 70
  end

  test "returns price and zone classifications with the signal" do
    good, signal, boll_zone, stave_zone = classify(112)

    assert good
    assert_equal "SEL7", signal
    assert_equal 1, boll_zone
    assert_equal 2, stave_zone
  end

  private

  def classify(price, **overrides)
    options = @bands.merge(overrides)
    @engine.send(:_good_signal, price, **options)
  end

  def assert_signal(expected, price, **overrides)
    assert_equal expected, classify(price, **overrides)[1]
  end

  def previous(price:, **overrides)
    @bands.merge(overrides).merge(price: price)
  end
end
