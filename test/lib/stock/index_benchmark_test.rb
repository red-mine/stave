require "test_helper"
require "tempfile"
require "fileutils"

class StockIndexBenchmarkTest < ActiveSupport::TestCase
  def with_index_file(area:, code:, records:)
    Dir.mktmpdir do |root|
      lday_dir = File.join(root, area, "lday")
      FileUtils.mkdir_p(lday_dir)
      File.open(File.join(lday_dir, "#{code}.day"), "wb") do |file|
        records.each do |date, price|
          encoded_date = date.year * 10_000 + date.month * 100 + date.day
          file.write([encoded_date, 0, 0, 0, (price * 100).round].pack("L<5") + "\0" * 12)
        end
      end

      Stock.stub(:data_root, Pathname.new(root)) { yield }
    end
  end

  test "computes buy-and-hold total return from the first and last requested dates" do
    dates = 5.times.map { |index| Date.new(2026, 1, 1) + index }
    records = dates.map.with_index { |date, index| [date, 100.0 + index * 10.0] } # 100, 110, 120, 130, 140

    with_index_file(area: "sz", code: "sz399001", records: records) do
      result = Stock::IndexBenchmark.new("sz", dates).call

      assert result.available
      assert_equal "sz399001", result.index_code
      assert_equal 40.0, result.total_return
      assert_equal 100.0, result.prices[dates.first]
      assert_equal 140.0, result.prices[dates.last]
    end
  end

  test "forward-fills a requested date the index file has no record for" do
    dates = 4.times.map { |index| Date.new(2026, 1, 1) + index }
    records = [[dates[0], 100.0], [dates[2], 120.0], [dates[3], 130.0]] # dates[1] missing

    with_index_file(area: "sz", code: "sz399001", records: records) do
      result = Stock::IndexBenchmark.new("sz", dates).call

      assert result.available
      assert_equal 100.0, result.prices[dates[1]]
      assert_equal 30.0, result.total_return
    end
  end

  test "is unavailable for a market with no mapped index code" do
    result = Stock::IndexBenchmark.new("bj", [Date.new(2026, 1, 1)]).call

    refute result.available
    assert_nil result.index_code
    assert_nil result.total_return
    assert_empty result.prices
  end

  test "is unavailable when the mapped index file does not exist" do
    Dir.mktmpdir do |root|
      Stock.stub(:data_root, Pathname.new(root)) do
        result = Stock::IndexBenchmark.new("sz", [Date.new(2026, 1, 1)]).call

        refute result.available
      end
    end
  end
end
