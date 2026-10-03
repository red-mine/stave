module Stock
  class Stock

    def initialize(area, years, trim: 0, max_price: STAVE)
      @area    = area
      @years   = years
      @days    = years + STAVE
      @trim    = trim
      @max_price = max_price
      @models  = []
      @data_cache = {}
    end

    def result
      Rails.logger.info "Stave'in... #{STAVE} #{@area}"
      lohas_arel    = StocksCoefsLoha.arel_table
      lohas_area    = StocksCoefsLoha.where(lohas_arel[:area].eq(@area))
      years_by_stock = StocksCoefsYear.where(area: @area).index_by(&:stock)
      lohas_area.with_progress do |stock_loha|
        Progress.note   = stock_loha.stock.upcase
        stock_year = years_by_stock[stock_loha.stock]
        if stock_year
          stock  = StocksCoefsStav.find_or_initialize_by(
            stock: stock_loha.stock,
            area: stock_loha.area
          )
          stock.assign_attributes(
            stock:      stock_loha.stock,
            area:       stock_loha.area,
            loha:       stock_loha.coef,
            year:       stock_year.coef,
            price:      stock_loha.price,
            good:       stock_loha.good,
            lohas_signal: stock_loha.stave,
            year_signal:  stock_year.stave,
            boll3:      stock_loha.boll,
            stav3:      stock_loha.stav,
            boll1:      stock_year.boll,
            stav1:      stock_year.stav,
            date:       stock_loha.date,
          )
          stock.save
        end
      end
    end

    def models(table = nil)
      stocks   = _stocks
      complete = if table
        table.where(area: @area, years: @years).pluck(:stock, :date).to_h
      else
        {}
      end
      Rails.logger.info "Stock'in... #{@years} #{@area}"
      stocks.with_progress do |stock|
        Progress.note   = stock.upcase
        next if complete[stock] == _last_date(stock)
        model = _model(stock)
        next if model.empty?
        @models.push model
      end
      @models.sort_by! {
        |model|      -model[:coef]
      }
    end

    def staves(table)
      Rails.logger.info "Stave'in... #{@years} #{@area}"
      @models.with_progress do |model|
        Progress.note   = model[:stock].upcase
        price, stave, boll, stav = _price(model)
        stock      = table.find_or_initialize_by(
          stock:        model[:stock],
          area:         model[:area]
        )
        stock.assign_attributes(
          coef:         model[:coef],
          inter:        model[:inter],
          price:        model[:price],
          good:         price,
          stave:        stave,
          boll:         boll,
          stav:         stav,
          date:         model[:date],
          years:        @years
        )
        stock.save
      end
    end

    def aver(stock, days)
      aver   = _aver(stock, days)
      start  = days - 1
      last   = aver.size - 1
      aver   = aver.slice(start, last - start + 1)
      aver
    end

    def valid_model?(stock)
      _model(stock).present?
    end

    # Combined stave+channel reading for a single instrument. Indexes and
    # ETFs trade at point levels far above the stock sanity cap, so the
    # caller builds its engine with max_price: nil; anything without a
    # usable model (missing data or non-positive slope) returns nil. The
    # first slot of _price is the above-both-midlines boolean (stored in
    # the stocks tables' "good" column), not a price -- the last price
    # lives on model[:price].
    def signal_for(stock)
      model = _model(stock)
      return nil if model.empty?

      above, stave, boll, stav = _price(model)
      { model: model, above_midlines: above, stave: stave, boll: boll, stav: stav }
    end

    def trend(stock)
      trend  = _trend(stock)
      trend  = trend.pluck(:date, :price)
      trend
    end

    def stave_band(stock, stave, multi)
      data       = trend(stock)
      sqrt       = _sqrt(stock)
      if stave
        data.map! { |date, price|
          price  = price + sqrt * multi
          stave_ = [date, price.round(2)]
          stave_
        }
      else
        data.map! { |date, price|
          price  = price - sqrt * multi
          stave_ = [date, price.round(2)]
          stave_
        }
      end
      data
    end

    def boll(stock, days, boll)
      aver     = _aver(stock, days)
      sqrt     = _boll(stock, days)
      start    = aver.size - sqrt.size
      last     = aver.size - 1
      for index in start..last
        boll_  = aver[index][1]
        double = sqrt[index - start] * 2
        boll_  = if boll
          boll_ + double
        else
          boll_ - double
        end
        aver[index][1] = boll_.round(2)
      end
      boll     = aver.slice(start, last - start + 1)
      boll
    end

    private

    def _price(model)
      stock      = model[:stock]
      last       = model[:price]
      data       = _data(stock)
      prices     = data.pluck(:price)
      current_bands   = _signal_bands(prices, model)
      previous        = if prices.length > STAVE
        { price: prices[-2] }.merge(
          _signal_bands(prices[0...-1], model)
        )
      end

      _signal(
        last,
        **current_bands,
        previous: previous,
        falling_averages: _falling_averages?(prices)
      )
    end

    def _signal(last, boll:, mup:, mdn:, trend:, up1:, dn1:, up2:, dn2:,
                     previous: nil, falling_averages: false)
      # price
      price      = last > trend && last > boll
      # trend
      up1_trend  = last < up1 && last > trend
      up1_up2    = last > up1 && last < up2
      up2_top    = last > up2
      dn1_trend  = last > dn1 && last < trend
      dn1_dn2    = last < dn1 && last > dn2
      dn2_bot    = last < dn2
      # boll
      mup_boll   = last < mup && last > boll
      mup_top    = last > mup
      mdn_boll   = last > mdn && last < boll
      mdn_bot    = last < mdn
      # direction
      crossed_stave_top = previous && previous[:price] > previous[:up2] && last < up2
      crossed_channel_top = previous && previous[:price] > previous[:mup] && last < mup
      # stave
      stave      = "SAF1"  if  dn1_dn2    &&  mdn_boll # 1. SAFE - BUY !
      stave      = "SOX2"  if  up1_up2    &&  mup_top  # 2. SOAR - KEEP !!!
      stave      = "BUY5"  if  up1_trend  &&  mup_boll # 5. BUY  - more - positive ?
      if up1_up2 && mup_boll
        stave = if crossed_stave_top && crossed_channel_top
          "SEL3" # 3. Fell back inside both upper boundaries - sell
        elsif crossed_channel_top
          "SEL6" # 6. Fell back inside the channel - sell part
        else
          "SEL7" # 7. Extended sell zone / stave-top return
        end
      end
      if dn1_dn2 && mup_boll
        stave = falling_averages ? "WAT8" : "BUY4"
      end
      stave      = "WAT9"  if  dn2_bot    &&  mdn_bot  # 9. WAIT - can not buy !
      stave      = "CHP0"  if  dn2_bot    &&  mdn_boll # 0. CHIP - BUY ! (price recovered back into the channel)
      # boll
      boll       = boll
      boll       = +1   if mup_boll
      boll       = +2   if mup_top
      boll       = -1   if mdn_boll
      boll       = -2   if mdn_bot
      # stave
      stav       = +1 if up1_trend
      stav       = +2 if up1_up2
      stav       = +3 if up2_top
      stav       = -1 if dn1_trend
      stav       = -2 if dn1_dn2
      stav       = -3 if dn2_bot
      return          price, stave, boll, stav
    end

    def _signal_bands(prices, model)
      return {} if prices.empty? || model.empty?

      boll       = prices.last(STAVE).sum.fdiv(STAVE).round(2)

      # Preserve the legacy Bollinger alignment while calculating only its
      # final value instead of rebuilding the complete series three times.
      averages   = _move(prices, STAVE)
      distances  = averages.each_with_index.map do |average, index|
        (prices[index] - average) ** 2
      end
      deviation  = Math.sqrt(distances.last(STAVE).sum.fdiv(STAVE)).round(2)

      last_index = prices.length - 1
      trend      = (model[:coef] * last_index + model[:inter]).round(2)
      residuals  = prices.each_with_index.drop(STAVE - 1).map do |price, index|
        expected = model[:coef] * (index + STAVE - 1) + model[:inter]
        (price - expected.round(2)) ** 2
      end
      sqrt       = if residuals.empty?
        0.0
      else
        Math.sqrt(residuals.sum.fdiv(residuals.length))
      end

      {
        boll: boll,
        mup: (boll + deviation * 2).round(2),
        mdn: (boll - deviation * 2).round(2),
        trend: trend,
        up1: (trend + sqrt).round(2),
        dn1: (trend - sqrt).round(2),
        up2: (trend + sqrt * 2).round(2),
        dn2: (trend - sqrt * 2).round(2)
      }
    end

    def _falling_averages?(prices)
      lookback = 20
      [5, 10, 20, 40].all? do |window|
        next false if prices.length < window + lookback

        current = prices.last(window).sum.fdiv(window)
        previous = prices[0...-lookback].last(window).sum.fdiv(window)
        current < previous
      end
    end

    def _move(price, days)
      move   = price.each_cons(days).map {
        |aver| aver.reduce(&:+).fdiv(days).round(2)
      }
      move
    end

    def _aver(stock, days)
      data   = _data(stock)
      price  = data.pluck(:price)
      aver   = _move(price, days)
      start  = price.size - aver.size
      last   = price.size - 1
      for index in start..last
        data[index][:price] = aver[index - start]
      end
      data.pluck(:date, :price)
    end

    def _dist(stock, days)
      data   = _days(stock, days).pluck(:date, :price)
      aver   = _aver(stock, days)
      data.each_with_index do |data_, index|
        distance = data_[1] - aver[index][1]
        data[index][1] = distance ** 2
      end
      data
    end

    def _boll(stock, days)
      dist   = _dist(stock, days)
      dist.map! { |date, price| price }
      sqrt   = _move(dist, days)
      sqrt.each_with_index do |data, index|
        sqrt[index] = Math.sqrt(data).round(2)
      end
      sqrt
    end

    def _days(stock, days)
      data   = _data(stock)
      start  = STAVE - days
      last   = data.size - 1
      data   = data.slice(start, last - start + 1)
      data
    end

    def _stave(stock)
      data   = _data(stock)
      start  = STAVE - 1
      last   = data.size - 1
      data   = data.slice(start, last - start + 1)
      data
    end

    def _read_record(file, index)
      _record(file.read(32), 0, index)
    end

    def _record(binary, offset, index)
      values = binary.unpack("L<5", offset: offset)
      date   = values[0]
      year   = date / 10_000
      month  = date / 100 % 100
      day    = date % 100
      price  = values[4].fdiv(STAVE)
      stock  = {
        date:       Date.new(year, month, day),
        price:      price,
        index:      index
      }
      stock
    end

    def _data(stock)
      data = @data_cache[stock]
      unless data
        data = _read_data(stock)
        @data_cache[stock] = data
      end
      data.map(&:dup)
    end

    def _read_data(stock)
      path     = _path(stock)
      return [] unless File.file?(path) && File.size(path) > (@days + @trim) * 32

      File.open(path, "rb") do |file|
        file.seek(-(1 + @trim) * 32, IO::SEEK_END)
        last = _read_record(file, -1)
        return [] if @max_price && last[:price] > @max_price

        file.seek(-(@days + @trim) * 32, IO::SEEK_END)
        binary = file.read(@days * 32)
        return Array.new(@days) do |index|
          _record(binary, index * 32, index)
        end
      end
    end

    def _model(stock)
      price, date = _model_data(stock)
      return {} if price.empty?
      return {} if price.length < 2
      return {} if price.uniq.size < 2

      index  = (0...price.length).to_a
      count  = index.length
      sum_x  = index.sum
      sum_y  = price.sum
      sum_xx = index.sum { |value| value * value }
      sum_xy = index.zip(price).sum { |x, y| x * y }
      div    = count * sum_xx - sum_x * sum_x
      return {} if div.zero?
      coef   = (count * sum_xy - sum_x * sum_y).fdiv(div)
      return {} unless coef.finite?
      return {} if  coef < 1.0 / STAVE
      inter  = (sum_y - coef * sum_x).fdiv(count)
      return {} unless inter.finite?
      last   = price[-1]
      return {} unless last.finite?
      model  = {
        stock:      stock,
        area:       @area,
        coef:       coef,
        inter:      inter,
        price:      last,
        date:       date
      }
      model
    end

    def _model_data(stock)
      path = _path(stock)
      return [[], nil] unless File.file?(path) && File.size(path) > (@days + @trim) * 32

      File.open(path, "rb") do |file|
        file.seek(-(@days + @trim) * 32, IO::SEEK_END)
        binary = file.read(@days * 32)
        last_offset = (@days - 1) * 32
        last = _record(binary, last_offset, -1)
        return [[], nil] if @max_price && last[:price] > @max_price

        prices = Array.new(@days) do |index|
          binary.unpack1("L<", offset: index * 32 + 16).fdiv(STAVE)
        end
        [prices, last[:date]]
      end
    end

    def _last_date(stock)
      path = _path(stock)
      return nil unless File.file?(path) && File.size(path) >= (1 + @trim) * 32

      File.open(path, "rb") do |file|
        file.seek(-(1 + @trim) * 32, IO::SEEK_END)
        _read_record(file, -1)[:date]
      end
    end

    def _trend(stock)
      stave  = _stave(stock)
      model  = _model(stock)
      return [] if model.empty?
      stave.each do |data|
        price = model[:coef] * data[:index] + model[:inter]
        data[:price] = price.round(2)
      end
      stave
    end

    def _sqrt(stock)
      stave  = _stave(stock)
      trend  = _trend(stock)
      return 0.0 if trend.empty?
      stave.each_with_index do |data, index|
        price = stave[index][:price] - trend[index][:price]
        stave[index][:price] = price ** 2
      end
      price  = stave.pluck(:price)
      sum    = price.sum
      div    = sum / trend.size
      sqrt   = Math.sqrt(div)
      sqrt
    end

    def _stocks
      stocks = []
      files  = _files
      files.each do |file|
        stock = file[0,8]
        stocks.push stock
      end
      stocks
    end

    def _files
      Dir.children(_base).select do |file|
        path = _path(file[0, 8])
        File.file?(path) && File.size(path) > (@days + @trim) * 32
      end
    end

    def _path(stock)
      path   = _base + stock + ".day"
      path
    end

    def _base
      File.join(::Stock.data_root, @area, "lday") + File::SEPARATOR
    end

  end
end
