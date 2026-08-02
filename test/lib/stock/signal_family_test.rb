require "test_helper"

class StockSignalFamilyTest < ActiveSupport::TestCase
  test "requires agreement for buys and treats either sell horizon as an alert" do
    assert_equal "buy", Stock::SignalFamily.classify("BUY5", "SAF1")
    assert_equal "sell", Stock::SignalFamily.classify("BUY5", "SEL7")
    assert_equal "watch", Stock::SignalFamily.classify("WAT9", "BUY5")
    assert_equal "watch", Stock::SignalFamily.classify(nil, "BUY5")
  end

  test "provides user-facing family labels" do
    assert_equal "Buy agreement", Stock::SignalFamily.label("buy")
    assert_equal "Sell alert", Stock::SignalFamily.label("sell")
    assert_equal "Watch", Stock::SignalFamily.label("watch")
  end
end
