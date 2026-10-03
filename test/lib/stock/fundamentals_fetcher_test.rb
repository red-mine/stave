require "test_helper"

class Stock::FundamentalsFetcherTest < ActiveSupport::TestCase
  test "upserts quote and report fields for known stocks" do
    create_stock "sz000001"
    create_stock "sz000002"
    reports = {
      "000001.SZ" => {
        name: "平安银行", report_date: Date.new(2026, 6, 30),
        roe: 5.22, revenue_yoy: 1.78, profit_yoy: 3.3
      }
    }
    transport = ->(_url, _params) { quote_payload }

    counts = Stock::FundamentalsFetcher.new(Stock::SZSTK, transport: transport).call(reports: reports)

    assert_equal 2, counts[:stocks]
    assert_equal 2, counts[:upserted]
    assert_equal 1, counts[:with_report]
    assert_equal 0, counts[:skipped]

    first = StockFundamental.find_by!(stock: "sz000001", area: Stock::SZSTK)
    assert_equal "平安银行", first.name
    assert_in_delta 11.57, first.price
    assert_in_delta 5.17, first.pe_ttm
    assert_in_delta 0.48, first.pb
    assert_equal 224_526_473_551, first.market_cap
    assert_equal Date.new(2026, 6, 30), first.report_date
    assert_in_delta 5.22, first.roe
    assert_in_delta 1.78, first.revenue_yoy
    assert_in_delta 3.3, first.profit_yoy
    assert first.fetched_at.present?

    second = StockFundamental.find_by!(stock: "sz000002", area: Stock::SZSTK)
    assert_equal "万科A", second.name
    assert_nil second.price
    assert_nil second.pe_ttm
    assert_nil second.roe
    assert_nil second.report_date
  end

  test "skips stocks missing from the quote response" do
    create_stock "sz000001"
    create_stock "sz000099"
    transport = ->(_url, _params) { quote_payload }

    counts = Stock::FundamentalsFetcher.new(Stock::SZSTK, transport: transport).call(reports: {})

    assert_equal 1, counts[:upserted]
    assert_equal 1, counts[:skipped]
    assert StockFundamental.exists?(stock: "sz000001")
    assert_not StockFundamental.exists?(stock: "sz000099")
  end

  test "skips fund and ETF codes that carry no meaningful fundamentals" do
    create_stock "sz150001"
    transport = ->(_url, _params) { quote_payload }

    counts = Stock::FundamentalsFetcher.new(Stock::SZSTK, transport: transport).call(reports: {})

    assert_equal 0, counts[:stocks]
    assert_equal 0, counts[:upserted]
    assert_not StockFundamental.exists?
  end

  test "purges fund rows left over from before the filter existed" do
    StockFundamental.create!(area: Stock::SZSTK, stock: "sz150001", fetched_at: Time.current)
    create_stock "sz000001"
    transport = ->(_url, _params) { quote_payload }

    Stock::FundamentalsFetcher.new(Stock::SZSTK, transport: transport).call(reports: {})

    assert_not StockFundamental.exists?(stock: "sz150001")
    assert StockFundamental.exists?(stock: "sz000001")
  end

  test "matches Beijing Exchange reports by company name after the 920xxx code switch" do
    create_stock "sz000001"
    reports = {
      "920000.SZ" => {
        name: "平安银行", report_date: Date.new(2026, 6, 30),
        roe: 5.22, revenue_yoy: 1.78, profit_yoy: 3.3
      }
    }
    transport = ->(_url, _params) { quote_payload }

    Stock::FundamentalsFetcher.new(Stock::SZSTK, transport: transport).call(reports: reports)

    record = StockFundamental.find_by!(stock: "sz000001")
    assert_equal Date.new(2026, 6, 30), record.report_date
    assert_in_delta 5.22, record.roe
  end

  test "re-running refreshes rows in place" do
    create_stock "sz000001"
    transport = ->(_url, _params) { quote_payload }

    Stock::FundamentalsFetcher.new(Stock::SZSTK, transport: transport).call(reports: {})
    transport = ->(_url, _params) { quote_payload(price: "99.0") }
    Stock::FundamentalsFetcher.new(Stock::SZSTK, transport: transport).call(reports: {})

    record = StockFundamental.find_by!(stock: "sz000001")
    assert_equal 1, StockFundamental.count
    assert_in_delta 99.0, record.price
  end

  test "fetch_reports paginates every page and keys rows by SECUCODE" do
    calls = []
    transport = ->(_url, params) {
      calls << params["pageNumber"]
      page = params["pageNumber"]
      {
        "success" => true,
        "result" => {
          "pages" => 2,
          "data" => page == 1 ? report_rows("000001.SZ", "600000.SH") : report_rows("920002.BJ")
        }
      }.to_json
    }

    reports = Stock::FundamentalsFetcher.fetch_reports(transport)

    assert_equal [1, 2], calls
    assert_equal %w[000001.SZ 600000.SH 920002.BJ].sort, reports.keys.sort
    assert_equal Date.new(2026, 6, 30), reports["000001.SZ"][:report_date]
    assert_in_delta 5.22, reports["000001.SZ"][:roe]
  end

  test "fetch_reports raises when Eastmoney reports failure" do
    transport = ->(_url, _params) { { "success" => false, "message" => "throttled" }.to_json }

    error = assert_raises(RuntimeError) { Stock::FundamentalsFetcher.fetch_reports(transport) }
    assert_match(/page 1/, error.message)
    assert_match(/throttled/, error.message)
  end

  test "transport retries transient network failures then succeeds" do
    attempts = 0
    ok = Net::HTTPOK.new("1.1", "200", "OK")
    ok.instance_variable_set(:@read, true)
    ok.instance_variable_set(:@body, '{"ok":true}')
    flaky = ->(*_args, &_block) {
      attempts += 1
      raise OpenSSL::SSL::SSLError, "unexpected eof" if attempts <= 2

      ok
    }

    Net::HTTP.stub(:start, flaky) do
      result = Stock::FundamentalsFetcher.transport(pause: 0).call(Stock::FundamentalsFetcher::QUOTE_URL, {})
      assert_equal '{"ok":true}', result
    end
    assert_equal 3, attempts
  end

  test "transport gives up after repeated failures" do
    calls = 0
    down = ->(*_args, &_block) {
      calls += 1
      raise OpenSSL::SSL::SSLError, "unexpected eof"
    }

    Net::HTTP.stub(:start, down) do
      assert_raises(OpenSSL::SSL::SSLError) do
        Stock::FundamentalsFetcher.transport(pause: 0).call(Stock::FundamentalsFetcher::QUOTE_URL, {})
      end
    end
    assert_equal Stock::FundamentalsFetcher::MAX_ATTEMPTS, calls
  end

  private

  def create_stock(stock)
    StocksCoefsStav.create!(
      stock: stock, area: Stock::SZSTK, date: Date.new(2026, 9, 30), price: 10,
      loha: 0.03, year: 0.02, lohas_signal: "BUY5", year_signal: "SAF1",
      boll3: 1, stav3: 1, boll1: 0, stav1: -1
    )
  end

  # Tencent answers GBK-encoded `v_sz000001="1~name~code~price~…~";` rows where
  # the SZ layout keeps PE TTM at 39, market cap at 45, PB at 46 and PE at 52.
  def quote_payload(price: "11.57", pe_ttm: "5.17", pe: "4.37", pb: "0.48", market_cap_yi: "2245.26473551")
    first = tencent_row("sz000001", "平安银行",
      price: price, pe_ttm: pe_ttm, pe: pe, pb: pb, market_cap_yi: market_cap_yi)
    second = tencent_row("sz000002", "万科A",
      price: "-", pe_ttm: nil, pe: nil, pb: nil, market_cap_yi: nil)
    [first, second].join("\n").encode("GB18030")
  end

  def tencent_row(stock, name, price:, pe_ttm:, pe:, pb:, market_cap_yi:)
    fields = Array.new(53, "-")
    fields[1] = name
    fields[2] = stock.delete_prefix("sz")
    fields[3] = price
    fields[39] = pe_ttm || "-"
    fields[45] = market_cap_yi || "-"
    fields[46] = pb || "-"
    fields[52] = pe || "-"
    %(v_#{stock}="#{fields.join("~")}";)
  end

  def report_rows(*secucodes)
    secucodes.map do |secucode|
      {
        "SECURITY_CODE" => secucode.split(".").first,
        "SECURITY_NAME_ABBR" => "示例",
        "SECUCODE" => secucode,
        "REPORTDATE" => "2026-06-30 00:00:00",
        "WEIGHTAVG_ROE" => 5.22,
        "YSTZ" => 1.78,
        "SJLTZ" => 3.3
      }
    end
  end
end
