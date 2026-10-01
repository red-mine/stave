require "test_helper"
require "tmpdir"
require "fileutils"

class StaveDataTest < ActiveSupport::TestCase
  test "data dates distinguish a historical stock from its current market" do
    StocksCoefsStav.create!(stock: "sz000522", area: Stock::SZSTK, date: Date.new(2013, 3, 13))
    StocksCoefsStav.create!(stock: "sz000001", area: Stock::SZSTK, date: Date.new(2026, 7, 31))
    StocksCoefsStav.create!(stock: "sh600000", area: Stock::SHSTK, date: Date.new(2026, 8, 1))

    dates = Stock::Stave.new(Stock::SZSTK, Stock::STAVE).data_dates("sz000522")

    assert_equal [Date.new(2013, 3, 13), Date.new(2026, 7, 31)], dates
  end

  test "chart data is market-scoped and ordered chronologically" do
    stock = "shared001"
    StocksStaveYear.create!(stock: stock, area: Stock::SZSTK, years: "price", date: Date.new(2026, 7, 1), price: 12)
    StocksStaveYear.create!(stock: stock, area: Stock::SZSTK, years: "price", date: Date.new(2026, 5, 1), price: 10)
    StocksStaveYear.create!(stock: stock, area: Stock::SHSTK, years: "price", date: Date.new(2026, 6, 1), price: 99)

    _lohas, years, = Stock::Stave.new(Stock::SZSTK, Stock::STAVE).chart_data(stock)

    assert_equal [
      [Date.new(2026, 5, 1), 10.0],
      [Date.new(2026, 7, 1), 12.0]
    ], years.first[:data]
  end

  test "chart series have unique descriptive labels" do
    lohas, _years, bolls, = Stock::Stave.new(Stock::SZSTK, Stock::STAVE).chart_data("labels001")

    assert_equal ["收盘价", "趋势线", "+1SD", "-1SD", "乐观线 (+2SD)", "悲观线 (-2SD)"], lohas.pluck(:name)
    assert_equal ["通道中轨", "通道上轨", "通道下轨"], bolls.drop(1).pluck(:name)
    assert_equal lohas.length, lohas.pluck(:name).uniq.length
    assert_equal bolls.length, bolls.pluck(:name).uniq.length
  end
end

class StaveResultTest < ActiveSupport::TestCase
  # Enough history for the longest series a result builds (LOHAS + STAVE
  # records) plus a margin, so both engines get a full window to fit.
  HISTORY = Stock::LOHAS + Stock::STAVE + 25

  private

  # A .day file is 32-byte records: an encoded date and four prices, of which
  # only the last is read. `slope` is in price ticks per record, and the base
  # keeps a falling series from running into a negative encoded price.
  def day_file(slope)
    base = slope.negative? ? 3_000 : 1_000
    start_date = Date.new(2024, 1, 1)
    HISTORY.times.map do |index|
      date = start_date + index
      encoded_date = date.year * 10_000 + date.month * 100 + date.day
      [encoded_date, 0, 0, 0, base + index * slope].pack("L<5") + "\0" * 12
    end.join
  end

  def with_market(files)
    Dir.mktmpdir do |root|
      directory = File.join(root, Stock::SZSTK, "lday")
      FileUtils.mkdir_p(directory)
      files.each do |stock, slope|
        File.binwrite(File.join(directory, "#{stock}.day"), day_file(slope))
      end
      Stock.stub(:data_root, Pathname.new(root)) { yield directory }
    end
  end

  def stored_series(stock)
    StocksStaveLoha.where(stock: stock, area: Stock::SZSTK)
      .order(:years, :date).pluck(:years, :date, :price)
  end

  test "stores every series for a stock both engines accept" do
    stock = "sz000001"
    StocksCoefsStav.create!(stock: stock, area: Stock::SZSTK, date: Date.new(2026, 8, 31))

    with_market({ stock => 2 }) { Stock::Stave.new(Stock::SZSTK, Stock::YEARS).result }

    [StocksStaveLoha, StocksStaveYear, StocksBollsLoha, StocksBollsYear].each do |table|
      refute_empty table.where(stock: stock, area: Stock::SZSTK), "#{table.name} stored no rows"
    end
  end

  test "LOHAS series are sampled quarterly and year series monthly" do
    stock = "sz000001"
    StocksCoefsStav.create!(stock: stock, area: Stock::SZSTK, date: Date.new(2026, 8, 31))

    with_market({ stock => 2 }) { Stock::Stave.new(Stock::SZSTK, Stock::YEARS).result }

    lohas_dates = StocksStaveLoha.where(stock: stock, area: Stock::SZSTK, years: "price").pluck(:date)
    year_dates = StocksStaveYear.where(stock: stock, area: Stock::SZSTK, years: "price").pluck(:date)

    assert_operator lohas_dates.length, :>, 1
    assert_operator year_dates.length, :>, 1
    assert lohas_dates.all? { |date| date == date.beginning_of_quarter }, "LOHAS series is not quarter-sampled"
    assert year_dates.all? { |date| date.day == 1 }, "year series is not month-sampled"
  end

  test "every series in a table shares one date axis" do
    stock = "sz000001"
    StocksCoefsStav.create!(stock: stock, area: Stock::SZSTK, date: Date.new(2026, 8, 31))

    with_market({ stock => 2 }) { Stock::Stave.new(Stock::SZSTK, Stock::YEARS).result }

    [[StocksStaveLoha, %w[price trend up1 dn1 top bot]], [StocksBollsLoha, %w[price bolls mup mdn]]].each do |table, keys|
      axes = keys.map { |key| table.where(stock: stock, area: Stock::SZSTK, years: key).order(:date).pluck(:date) }

      refute_empty axes.first, "#{table.name} stored no series"
      assert_equal 1, axes.uniq.length, "#{table.name} series disagree on their dates"
    end
  end

  # A unique index on [area, stock, years, date] already stops a repeat run from
  # adding rows, so counting rows proves nothing. What has to hold is that the
  # stored values are replaced, not kept: the tables are cleared before the new
  # series is written.
  test "a second run replaces the stored values with fresh ones" do
    stock = "sz000001"
    StocksCoefsStav.create!(stock: stock, area: Stock::SZSTK, date: Date.new(2026, 8, 31))

    with_market({ stock => 2 }) do |directory|
      Stock::Stave.new(Stock::SZSTK, Stock::YEARS).result
      before = stored_series(stock)

      File.binwrite(File.join(directory, "#{stock}.day"), day_file(6))
      Stock::Stave.new(Stock::SZSTK, Stock::YEARS).result
      after = stored_series(stock)

      assert_operator before.length, :>, 0
      assert_equal before.length, after.length
      refute_equal before, after, "the second run kept the first run's values"
    end
  end

  test "a stock without a rising trend is dropped rather than stored" do
    rising = "sz000001"
    falling = "sz000002"
    [rising, falling].each do |stock|
      StocksCoefsStav.create!(stock: stock, area: Stock::SZSTK, date: Date.new(2026, 8, 31))
    end

    with_market({ rising => 2, falling => -2 }) { Stock::Stave.new(Stock::SZSTK, Stock::YEARS).result }

    assert StocksCoefsStav.exists?(stock: rising, area: Stock::SZSTK)
    refute StocksCoefsStav.exists?(stock: falling, area: Stock::SZSTK)
    assert_empty StocksStaveLoha.where(stock: falling, area: Stock::SZSTK)
  end
end
