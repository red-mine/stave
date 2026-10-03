require "net/http"
require "json"

module Stock
  # Downloads per-stock fundamentals from public HTTP endpoints:
  #
  # - Tencent batch quotes (qt.gtimg.cn) for name, price, PE, PE TTM, PB and
  #   total market cap. Eastmoney's push2 endpoint consistently drops Ruby's
  #   TLS connections on some networks, so quotes come from Tencent instead.
  # - the Eastmoney DataCenter performance report (RPT_LICO_FN_CPD, ISNEW=1)
  #   for each stock's newest published report: weighted ROE, revenue YoY,
  #   net-profit YoY.
  #
  # The transport is injectable so tests can replay fixtures without network.
  class FundamentalsFetcher
    QUOTE_URL = "https://qt.gtimg.cn/q="
    REPORT_URL = "https://datacenter-web.eastmoney.com/api/data/v1/get"
    QUOTE_BATCH = 60
    REPORT_PAGE = 500
    PAGE_PAUSE = 0.1
    MAX_ATTEMPTS = 4

    # Tencent's ~-separated quote rows use the same layout on every market:
    # 39 = PE (TTM), 45 = total market cap (yi), 46 = PB, 52 = PE (static).
    # Indices were cross-checked against known quotes (Moutai PE TTM ~19,
    # PB ~6.3; ICBC PB ~0.74) for SZ, SH and BJ stocks alike — an earlier
    # per-market offset for SH/BJ read garbage (empty PE TTM, PB of -1).
    QUOTE_LAYOUTS = {
      pe_ttm: 39, pe: 52, market_cap_yi: 45, pb: 46, min_fields: 53
    }.freeze

    # The stock universe also carries funds and ETFs (SZ 15/16/18xxxx,
    # SH 50/51/52/56/58xxxx), whose PE/PB/cap fields are meaningless. Leave
    # them untouched instead of storing junk fundamentals.
    FUND_CODE = /\A(sz1[568]\d{4}|sh5[01268]\d{4})\z/

    # Transport lambda: (url, params) -> raw response body String. Transient
    # network failures (SSL resets, timeouts, 5xx) are retried with backoff —
    # these endpoints sit behind CDNs that occasionally drop connections.
    def self.transport(pause: PAGE_PAUSE)
      ->(url, params) {
        uri = URI(url)
        uri.query = URI.encode_www_form(params) if params.present?
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "StockStave/#{VERSION}"

        attempt = 0
        begin
          sleep pause
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |session|
            session.request(request)
          end
          raise "Quote request failed: HTTP #{response.code} for #{uri.host}#{uri.path}" unless response.is_a?(Net::HTTPSuccess)

          response.body
        rescue StandardError
          attempt += 1
          raise if attempt >= MAX_ATTEMPTS

          sleep pause * (2**attempt)
          retry
        end
      }
    end

    # Every stock's newest published report, keyed by Eastmoney SECUCODE
    # ("000001.SZ"). Shared across markets, so the refresh task fetches it
    # once and hands it to each area's fetcher.
    def self.fetch_reports(transport)
      reports = {}
      page = 1
      loop do
        body = transport.call(REPORT_URL, {
          "reportName" => "RPT_LICO_FN_CPD",
          "columns" => "SECURITY_CODE,SECURITY_NAME_ABBR,SECUCODE,REPORTDATE,WEIGHTAVG_ROE,YSTZ,SJLTZ",
          "filter" => '(ISNEW="1")',
          "sortColumns" => "SECURITY_CODE",
          "sortTypes" => "1",
          "pageSize" => REPORT_PAGE,
          "pageNumber" => page,
          "source" => "DataCenter"
        })
        payload = JSON.parse(body)
        raise "Eastmoney report request failed on page #{page}: #{payload['message']}" unless payload["success"]

        result = payload["result"] || {}
        rows = result["data"] || []
        rows.each do |row|
          code = row["SECUCODE"].to_s
          next if code.empty?

          reports[code] = {
            name: row["SECURITY_NAME_ABBR"],
            report_date: parse_date(row["REPORTDATE"]),
            roe: to_float(row["WEIGHTAVG_ROE"]),
            revenue_yoy: to_float(row["YSTZ"]),
            profit_yoy: to_float(row["SJLTZ"])
          }
        end

        pages = result["pages"].to_i
        break if pages.zero? || page >= pages

        page += 1
      end
      reports
    end

    def initialize(area, transport: self.class.transport)
      @area = area
      @transport = transport
    end

    # Returns { stocks:, upserted:, with_report:, skipped: } counts. Stocks
    # missing from the quote response (suspended, delisted or unmatched) are
    # counted as skipped and left untouched.
    def call(reports:)
      stocks = StocksCoefsStav.where(area: @area).distinct.pluck(:stock).grep_v(FUND_CODE)
      purge_fund_rows
      quotes = fetch_quotes(stocks)
      now = Time.current

      # Beijing Exchange stocks kept their old codes here while Eastmoney
      # switched them to 920xxx SECUCODEs ("430418.BJ" -> "920xxx.BJ"), so the
      # report table is also indexed by company name as a fallback.
      reports_by_name = reports.values.index_by { |report| report[:name] }

      upserted = 0
      with_report = 0
      stocks.each do |stock|
        quote = quotes[stock]
        next unless quote

        code = stock.delete_prefix(@area)
        report = reports["#{code}.#{@area.upcase}"] || reports_by_name[quote[:name]]
        with_report += 1 if report

        attributes = {
          name: quote[:name] || (report && report[:name]),
          price: quote[:price], pe: quote[:pe], pe_ttm: quote[:pe_ttm], pb: quote[:pb],
          market_cap: quote[:market_cap],
          report_date: report && report[:report_date],
          roe: report && report[:roe],
          revenue_yoy: report && report[:revenue_yoy],
          profit_yoy: report && report[:profit_yoy],
          fetched_at: now
        }
        StockFundamental.upsert(attributes.merge(area: @area, stock: stock), unique_by: %i[area stock])
        upserted += 1
      end

      { stocks: stocks.size, upserted: upserted, with_report: with_report, skipped: stocks.size - upserted }
    end

    private

    # Funds/ETFs are no longer refreshed, so drop rows written before the
    # filter existed. SZ regexes would need a REGEXP function; do it in Ruby.
    def purge_fund_rows
      stale = StockFundamental.where(area: @area).pluck(:stock).grep(FUND_CODE)
      StockFundamental.where(area: @area, stock: stale).delete_all if stale.any?
    end

    # Tencent answers with one `v_<stock>="…";` line per code, GBK encoded and
    # ~-separated. Rows that are too short to trust (suspended stocks) are
    # ignored, which marks the stock as skipped in #call.
    def fetch_quotes(stocks)
      layout = QUOTE_LAYOUTS
      quotes = {}
      stocks.each_slice(QUOTE_BATCH) do |batch|
        body = @transport.call("#{QUOTE_URL}#{batch.join(",")}", nil)
        body.to_s.force_encoding("GB18030").encode("UTF-8", invalid: :replace, undef: :replace).scan(/^v_(\w+)="([^"]*)";/) do |stock, payload|
          fields = payload.split("~")
          next if fields.size < layout[:min_fields] || fields[2].empty?

          market_cap_yi = self.class.to_float(fields[layout[:market_cap_yi]])
          quotes[stock] = {
            name: fields[1].presence,
            price: self.class.to_float(fields[3]),
            pe: self.class.to_float(fields[layout[:pe]]),
            pe_ttm: self.class.to_float(fields[layout[:pe_ttm]]),
            pb: self.class.to_float(fields[layout[:pb]]),
            market_cap: market_cap_yi.nil? ? nil : (market_cap_yi * 100_000_000).round
          }
        end
      end
      quotes
    end

    def self.parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    def self.to_float(value)
      Float(value, exception: false)
    end
  end
end
