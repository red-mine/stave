module Stock
  class Stave
    STAVE_SERIES_NAMES = {
      price: "收盘价",
      trend: "趋势线",
      up1: "+1SD",
      dn1: "-1SD",
      top: "乐观线 (+2SD)",
      bot: "悲观线 (-2SD)"
    }.freeze

    BOLLS_SERIES_NAMES = {
      price: "收盘价",
      bolls: "通道中轨",
      mup: "通道上轨",
      mdn: "通道下轨"
    }.freeze

    def initialize(area, years)
      @area    = area
      @years   = years
    end

    def result
      Rails.logger.info "Store'in... #{STAVE} #{@area}"
      staves_arel   = StocksCoefsStav.arel_table
      staves_area   = StocksCoefsStav.where(staves_arel[:area].eq(@area))
      staves_area.with_progress do |stock_stav|
        stock  = stock_stav.stock
        Progress.note = stock.upcase
        ActiveRecord::Base.transaction do
          [StocksStaveLoha, StocksStaveYear, StocksBollsLoha, StocksBollsYear].each do |table|
            table.where(stock: stock, area: @area).delete_all
          end
        loha_engine = _engin(@area, LOHAS)
        year_engine = _engin(@area, YEARS)
        unless loha_engine.valid_model?(stock) && year_engine.valid_model?(stock)
          StocksCoefsStav.where(stock: stock, area: @area).delete_all
          next
        end

        # Build series data for both engines
        data = {
          lohas_price:  nil, lohas_trend:  nil, lohas_up1:   nil, lohas_dn1:   nil, lohas_top:   nil, lohas_bot:   nil,
          years_price:  nil, years_trend:  nil, years_up1:   nil, years_dn1:   nil, years_top:   nil, years_bot:   nil,
          lohas_bolls:  nil, lohas_mup:    nil, lohas_mdn:   nil,
          years_bolls:  nil, years_mup:    nil, years_mdn:   nil
        }
        # The channel tables plot the same price series as the stave tables, so
        # one series per engine fills both rather than building it twice.
        loha_price  = _series_price(loha_engine, LOHAS, stock)
        year_price  = _series_price(year_engine, YEARS, stock)
        data[:lohas_price], data[:lohas_trend], data[:lohas_up1], data[:lohas_dn1], data[:lohas_top], data[:lohas_bot] = _stave(loha_engine, LOHAS, stock, price: loha_price)
        data[:years_price], data[:years_trend], data[:years_up1], data[:years_dn1], data[:years_top], data[:years_bot] = _stave(year_engine, YEARS, stock, price: year_price)
        data[:lohas_bolls], data[:lohas_mup], data[:lohas_mdn] = _bolls(loha_engine, LOHAS, stock)
        data[:years_bolls], data[:years_mup], data[:years_mdn] = _bolls(year_engine, YEARS, stock)

        stave_series = [
          { table: StocksStaveLoha, prefix: :lohas, keys: %w[price trend up1 dn1 top bot] },
          { table: StocksStaveYear, prefix: :years, keys: %w[price trend up1 dn1 top bot] },
          { table: StocksBollsLoha,  prefix: :lohas, keys: %w[price bolls mup mdn] },
          { table: StocksBollsYear,  prefix: :years, keys: %w[price bolls mup mdn] }
        ]
        stave_series.each do |series|
          series[:keys].each do |key|
            column_name = "#{series[:prefix]}_#{key}"
            staves(series[:table], data[column_name.to_sym], stock, key)
          end
        end
        end
      end
      SignalSnapshot.capture!(@area)
    end

    def staves(table, stave, stock, years)
      rows = stave.map do |stave_|
        {
          stock:    stock,
          area:     @area,
          price:    stave_[1].round(2),
          date:     stave_[0],
          years:    years
        }
      end
      table.insert_all(rows) unless rows.empty?
    end

    def known_stock?(stock)
      StocksCoefsStav.exists?(stock: stock, area: @area)
    end

    def data_dates(stock)
      market_stocks = StocksCoefsStav.where(area: @area)
      [
        market_stocks.where(stock: stock).maximum(:date),
        market_stocks.maximum(:date)
      ]
    end

    def chart_data(stock)
      stave_lohas = _stave_data(stock, StocksStaveLoha)
      stave_years = _stave_data(stock, StocksStaveYear)
      bolls_lohas = _bolls_data(stock, StocksBollsLoha)
      bolls_years = _bolls_data(stock, StocksBollsYear)

      return stave_lohas, stave_years, bolls_lohas, bolls_years
    end

    def search(stock)
      staves_arel   = StocksCoefsStav.arel_table
      staves_area   = StocksCoefsStav.where(staves_arel[:area].eq(@area))
      stavs_date    = staves_area.maximum(:date)
      stocks_stavs  = if !stock.nil? and !stock.empty?
        staves_area.where(staves_arel[:stock].matches_any(["%" + stock + "%"]))
      else
        # Either horizon alone is enough to list a stock. Checking only
        # lohas_signal hid a stock whose LOHAS reading was nil but whose year
        # reading was a sell alert -- the one signal a reader most needs to see.
        # NULL <> '' is NULL, not true, so a row with no signal on either
        # horizon is still left out.
        staves_area.where(
          staves_arel[:lohas_signal].not_eq("").or(staves_arel[:year_signal].not_eq(""))
        )
      end
      stocks_stavs  = stocks_stavs.order(staves_arel[:price])
      return stocks_stavs, stavs_date
    end

    def strongest_buy_candidates(limit: 6)
      CandidateRanking.new(@area).call(limit: limit)
    end

    def trend_health(stock)
      record = StocksCoefsStav.where(stock: stock, area: @area).order(date: :desc).first
      return nil unless record

      {
        date: record.date,
        loha_slope: record.loha,
        year_slope: record.year,
        loha_status: Trend.classify(record.loha),
        year_status: Trend.classify(record.year)
      }
    end

    private

    def _engin(area, years)
      engine  = Stock.new(area, years)
      engine
    end

    def _week(stave)
      week    = []
      stave.each do |_stave|
        date  = _stave[0]
        wday  = date.wday
        if wday == 1
          week.push _stave
        end
      end
      week
    end

    def _month(stave)
      month   = []
      stave.each do |_stave|
        date  = _stave[0]
        mday  = date.mday
        if mday == 1
          month.push _stave
        end
      end
      month
    end

    def _quarter(stave)
      quarter = []
      stave.each do |_stave|
        date  = _stave[0]
        if date == date.beginning_of_quarter
          quarter.push _stave
        end
      end
      quarter
    end

    def _smooth(stave)
      smooth  = []
      _date   = nil
      _price  = 0
      stave.each do |_stave|
        date  = _stave[0]
        price = _stave[1]
        if !_date.nil?
          days  = (date   - _date).numerator
          dist  = (price  - _price) / days
          if days != 1
            days  = days - 1
            while days != 0
              day   = [date - days, price - dist * days]
              smooth.push day
              days  = days - 1
            end
          end
        end
        _date   = date
        _price  = price
        smooth.push _stave
      end
      smooth
    end

    def _better(stave, years)
      smooth = _smooth(stave)
      better = if years == LOHAS
        _quarter(smooth)
      else
        _month(smooth)
      end
      better
    end

    def _price(stocks, years, stock)
      start         = STAVE - SMUTH
      length        = years + 1
      price         = stocks.aver(stock, SMUTH).slice(start, length)
      price
    end

    def _series_price(stocks, years, stock)
      _better(_price(stocks, years, stock), years)
    end

    def _filter(table, filter, stock)
      arel  = table.arel_table
      stave = table
        .where(arel[:area].eq(@area))
        .where(arel[:stock].eq(stock))
        .where(arel[:years].eq(filter))
        .order(arel[:date])
        .pluck(arel[:date], arel[:price])
      stave
    end

    def _stave_data(stock, table)
      stave_price = _filter(table,  "price",  stock )
      stave_trend = _filter(table,  "trend",  stock )
      stave_up1   = _filter(table,  "up1",    stock )
      stave_dn1   = _filter(table,  "dn1",    stock )
      stave_top   = _filter(table,  "top",    stock )
      stave_bot   = _filter(table,  "bot",    stock )

      stave_data = [
        { name: STAVE_SERIES_NAMES[:price], data: stave_price },
        { name: STAVE_SERIES_NAMES[:trend], data: stave_trend },
        { name: STAVE_SERIES_NAMES[:up1],   data: stave_up1   },
        { name: STAVE_SERIES_NAMES[:dn1],   data: stave_dn1   },
        { name: STAVE_SERIES_NAMES[:top],   data: stave_top   },
        { name: STAVE_SERIES_NAMES[:bot],   data: stave_bot   }
      ]

      return stave_data
    end

    def _bolls_data(stock, table)
      bolls_price = _filter(table,  "price",  stock )
      bolls_bolls = _filter(table,  "bolls",  stock )
      bolls_mup   = _filter(table,  "mup",    stock )
      bolls_mdn   = _filter(table,  "mdn",    stock )

      bolls_data = [
        { name: BOLLS_SERIES_NAMES[:price], data: bolls_price },
        { name: BOLLS_SERIES_NAMES[:bolls], data: bolls_bolls },
        { name: BOLLS_SERIES_NAMES[:mup],   data: bolls_mup   },
        { name: BOLLS_SERIES_NAMES[:mdn],   data: bolls_mdn   }
      ]

      return bolls_data
    end

    def _stave(stocks, years, stock, price: nil)
      stave_price   = price || _series_price(stocks, years, stock)

      stave_trend   = stocks.trend(stock             )
      stave_up1     = stocks.stave_band(stock,  true,   1 )
      stave_dn1     = stocks.stave_band(stock,  false,  1 )
      stave_top     = stocks.stave_band(stock,  true,   2 )
      stave_bot     = stocks.stave_band(stock,  false,  2 )

      stave_trend   = _better(stave_trend,  years )
      stave_up1     = _better(stave_up1,    years )
      stave_dn1     = _better(stave_dn1,    years )
      stave_top     = _better(stave_top,    years )
      stave_bot     = _better(stave_bot,    years )

      return stave_price, stave_trend, stave_up1, stave_dn1, stave_top, stave_bot
    end


    # Returns no price: the channel table's price column is filled from the
    # stave series above, so a second one built here was thrown away.
    def _bolls(stocks, years, stock)
      bolls_bolls   = stocks.aver(stock, STAVE         )
      bolls_mup     = stocks.boll(stock, STAVE,  true  )
      bolls_mdn     = stocks.boll(stock, STAVE,  false )

      bolls_bolls   = _better(bolls_bolls,  years )
      bolls_mup     = _better(bolls_mup,    years )
      bolls_mdn     = _better(bolls_mdn,    years )

      return bolls_bolls, bolls_mup, bolls_mdn
    end

  end
end
