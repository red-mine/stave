require "test_helper"
require "tempfile"
require "fileutils"

class StockIndexSignalsTest < ActiveSupport::TestCase
  RECORDS = Stock::LOHAS + Stock::STAVE + 5

  def with_day_file(area:, code:, prices:)
    Dir.mktmpdir do |root|
      lday_dir = File.join(root, area, "lday")
      FileUtils.mkdir_p(lday_dir)
      start = Date.new(2023, 1, 1)
      File.open(File.join(lday_dir, "#{code}.day"), "wb") do |file|
        prices.each_with_index do |price, index|
          date = start + index
          encoded_date = date.year * 10_000 + date.month * 100 + date.day
          file.write([encoded_date, 0, 0, 0, (price * 100).round].pack("L<5") + "\0" * 12)
        end
      end

      Stock.stub(:data_root, Pathname.new(root)) { yield start + prices.size - 1 }
    end
  end

  def rising_prices(count = RECORDS)
    Array.new(count) { |index| 3_000 + index * 0.8 }
  end

  test "computes a reading for an index-priced instrument above the stock price cap" do
    prices = rising_prices

    with_day_file(area: "sh", code: "sh000001", prices: prices) do |last_date|
      reading = Stock::IndexSignals.new("sh").call.find { |entry| entry.code == "sh000001" }

      assert_equal :ok, reading.status
      assert_equal "上证综指", reading.name
      assert_equal last_date, reading.date
      assert_in_delta prices.last, reading.price, 0.01
      assert_in_delta 0.8, reading.loha, 0.01
      assert_in_delta 0.8, reading.year, 0.01
      assert_includes %w[buy sell watch], reading.family
      assert reading.lohas_signal.nil? || Stock::SignalCatalog::BY_CODE.key?(reading.lohas_signal)
    end
  end

  test "an instrument whose trend precondition fails reads as no_model" do
    prices = Array.new(RECORDS) { |index| 4_000 - index * 0.8 }

    with_day_file(area: "sh", code: "sh000001", prices: prices) do |_last_date|
      reading = Stock::IndexSignals.new("sh").call.find { |entry| entry.code == "sh000001" }

      assert_equal :no_model, reading.status
      assert_nil reading.price
      assert_nil reading.lohas_signal
      assert_nil reading.family
    end
  end

  test "an instrument without a daily file reads as no_data" do
    Dir.mktmpdir do |root|
      Stock.stub(:data_root, Pathname.new(root)) do
        reading = Stock::IndexSignals.new("sz").call.find { |entry| entry.code == "sz399001" }

        assert_equal :no_data, reading.status
      end
    end
  end

  test "a market without instruments yields an empty report" do
    assert_empty Stock::IndexSignals.new("bj").call
  end

  test "keeps the lohas reading when only the year window fails the slope bar" do
    prices = Array.new(RECORDS) { |index| index < 600 ? 3_000 + index * 0.8 : 3_480 - (index - 600) * 0.8 }

    with_day_file(area: "sh", code: "sh000001", prices: prices) do |last_date|
      reading = Stock::IndexSignals.new("sh").call.find { |entry| entry.code == "sh000001" }

      assert_equal :ok, reading.status
      assert_equal last_date, reading.date
      assert reading.loha.positive?
      assert_nil reading.year
      assert_nil reading.year_signal
      assert reading.lohas_signal.present?
    end
  end

  test "engines keep the stock price cap by default so the stock pipeline is unchanged" do
    prices = rising_prices

    with_day_file(area: "sh", code: "sh000001", prices: prices) do |_last_date|
      assert_nil Stock::Stock.new("sh", Stock::LOHAS).signal_for("sh000001")
      assert Stock::Stock.new("sh", Stock::LOHAS, max_price: nil).signal_for("sh000001").key?(:stave)
    end
  end
end
