module Stock
  class Stock

    def initialize(good_area, good_years)
      @good_area    = good_area
      @good_years   = good_years
      @good_days    = good_years + STAVE
      @good_models  = []
      @good_data_cache = {}
    end

    def good_result
      puts "Stave'in... #{STAVE} #{@good_area}"
      lohas_arel    = StocksCoefsLoha.arel_table
      lohas_area    = StocksCoefsLoha.where(lohas_arel[:area].eq(@good_area))
      years_by_stock = StocksCoefsYear.where(area: @good_area).index_by(&:stock)
      lohas_area.with_progress do |stock_loha|
        Progress.note   = stock_loha.stock.upcase
        stock_year = years_by_stock[stock_loha.stock]
        if stock_year
          good_stock  = StocksCoefsStav.find_or_initialize_by(
            stock: stock_loha.stock,
            area: stock_loha.area
          )
          good_stock.assign_attributes(
            stock:      stock_loha.stock,
            area:       stock_loha.area,
            loha:       stock_loha.coef,
            year:       stock_year.coef,
            price:      stock_loha.price,
            good:       stock_loha.good,
            lohas:      stock_loha.stave,
            years:      stock_year.stave,
            boll3:      stock_loha.boll,
            stav3:      stock_loha.stav,
            boll1:      stock_year.boll,
            stav1:      stock_year.stav,
            date:       stock_loha.date,
          )
          good_stock.save
        end
      end
    end

    def good_models(good_table = nil)
      good_stocks   = _good_stocks
      good_complete = if good_table
        good_table.where(area: @good_area, years: @good_years).pluck(:stock, :date).to_h
      else
        {}
      end
      puts "Stock'in... #{@good_years} #{@good_area}"
      good_stocks.with_progress do |good_stock|
        Progress.note   = good_stock.upcase
        next if good_complete[good_stock] == _good_last_date(good_stock)
        good_model      = _good_model(good_stock)
        next if           good_model.empty?
        @good_models.push good_model
      end
      @good_models.sort_by! {
        |good_model|      -good_model[:coef]
      }
    end

    def good_staves(good_table)
      puts "Stave'in... #{@good_years} #{@good_area}"
      @good_models.with_progress do |good_model|
        Progress.note   = good_model[:stock].upcase
        good_price, good_stave, good_boll, good_stav = _good_price(good_model)
        good_stock      = good_table.find_or_initialize_by(
          stock:        good_model[:stock],
          area:         good_model[:area]
        )
        good_stock.assign_attributes(
          coef:         good_model[:coef],
          inter:        good_model[:inter],
          price:        good_model[:price],
          good:         good_price,
          stave:        good_stave,
          boll:         good_boll,
          stav:         good_stav,
          date:         good_model[:date],
          years:        @good_years
        )
        good_stock.save
      end
    end

    def good_aver(good_stock, good_days)
      good_aver   = _good_aver(good_stock, good_days)
      good_start  = good_days - 1
      good_end    = good_aver.size - 1
      good_aver   = good_aver.slice(good_start, good_end - good_start + 1)
      good_aver
    end

    def valid_model?(good_stock)
      _good_model(good_stock).present?
    end

    def good_trend(good_stock)
      good_trend  = _good_trend(good_stock)
      good_trend  = good_trend.pluck(:date, :price)
      good_trend
    end

    def good_stave(good_stock, good_stave, good_multi)
      good_data       = good_trend(good_stock)
      good_sqrt       = _good_sqrt(good_stock)
      if good_stave
        good_data.map! { |good_date, good_price|
          good_price  = good_price + good_sqrt * good_multi
          good_stave_ = [good_date, good_price.round(2)]
          good_stave_
        }
      else
        good_data.map! { |good_date, good_price|
          good_price  = good_price - good_sqrt * good_multi
          good_stave_ = [good_date, good_price.round(2)]
          good_stave_
        }
      end
      good_data
    end

    def good_boll(good_stock, good_days, good_boll)
      good_aver     = _good_aver(good_stock, good_days)
      good_sqrt     = _good_boll(good_stock, good_days)
      good_start    = good_aver.size - good_sqrt.size
      good_end      = good_aver.size - 1
      for good_index in good_start..good_end
        good_boll_  = good_aver[good_index][1]
        good_double = good_sqrt[good_index - good_start] * 2
        good_boll_  = if good_boll
          good_boll_ + good_double
        else
          good_boll_ - good_double
        end
        good_aver[good_index][1] = good_boll_.round(2)
      end
      good_boll     = good_aver.slice(good_start, good_end - good_start + 1)
      good_boll
    end

    private

    def _good_price(good_model)
      good_stock      = good_model[:stock]
      good_last       = good_model[:price]
      good_data       = _good_data(good_stock)
      good_prices     = good_data.pluck(:price)
      current_bands   = _good_signal_bands(good_prices, good_model)
      previous        = if good_prices.length > STAVE
        { price: good_prices[-2] }.merge(
          _good_signal_bands(good_prices[0...-1], good_model)
        )
      end

      _good_signal(
        good_last,
        **current_bands,
        previous: previous,
        falling_averages: _falling_averages?(good_prices)
      )
    end

    def _good_signal(good_last, boll:, mup:, mdn:, trend:, up1:, dn1:, up2:, dn2:,
                     previous: nil, falling_averages: false)
      # price
      good_price      = good_last > trend && good_last > boll
      # trend
      good_up1_trend  = good_last < up1 && good_last > trend
      good_up1_up2    = good_last > up1 && good_last < up2
      good_up2_top    = good_last > up2
      good_dn1_trend  = good_last > dn1 && good_last < trend
      good_dn1_dn2    = good_last < dn1 && good_last > dn2
      good_dn2_bot    = good_last < dn2
      # boll
      good_mup_boll   = good_last < mup && good_last > boll
      good_mup_top    = good_last > mup
      good_mdn_boll   = good_last > mdn && good_last < boll
      good_mdn_bot    = good_last < mdn
      # direction
      crossed_stave_top = previous && previous[:price] > previous[:up2] && good_last < up2
      crossed_channel_top = previous && previous[:price] > previous[:mup] && good_last < mup
      # stave
      good_stave      = "SAF1"  if  good_dn1_dn2    &&  good_mdn_boll # 1. SAFE - BUY !
      good_stave      = "SOX2"  if  good_up1_up2    &&  good_mup_top  # 2. SOAR - KEEP !!!
      good_stave      = "BUY5"  if  good_up1_trend  &&  good_mup_boll # 5. BUY  - more - positive ?
      if good_up1_up2 && good_mup_boll
        good_stave = if crossed_stave_top && crossed_channel_top
          "SEL3" # 3. Fell back inside both upper boundaries - sell
        elsif crossed_channel_top
          "SEL6" # 6. Fell back inside the channel - sell part
        else
          "SEL7" # 7. Extended sell zone / stave-top return
        end
      end
      if good_dn1_dn2 && good_mup_boll
        good_stave = falling_averages ? "WAT8" : "BUY4"
      end
      good_stave      = "WAT9"  if  good_dn2_bot    &&  good_mdn_bot  # 9. WAIT - can not buy !
      good_stave      = "CHP0"  if  good_dn2_bot    &&  good_mdn_boll # 0. CHIP - BUY ! (price recovered back into the channel)
      # boll
      good_boll       = boll
      good_boll       = +1   if good_mup_boll
      good_boll       = +2   if good_mup_top
      good_boll       = -1   if good_mdn_boll
      good_boll       = -2   if good_mdn_bot
      # stave
      good_stav       = +1 if good_up1_trend
      good_stav       = +2 if good_up1_up2
      good_stav       = +3 if good_up2_top
      good_stav       = -1 if good_dn1_trend
      good_stav       = -2 if good_dn1_dn2
      good_stav       = -3 if good_dn2_bot
      return          good_price, good_stave, good_boll, good_stav
    end

    def _good_signal_bands(good_prices, good_model)
      return {} if good_prices.empty? || good_model.empty?

      good_boll       = good_prices.last(STAVE).sum.fdiv(STAVE).round(2)

      # Preserve the legacy Bollinger alignment while calculating only its
      # final value instead of rebuilding the complete series three times.
      good_averages   = _good_move(good_prices, STAVE)
      good_distances  = good_averages.each_with_index.map do |good_average, good_index|
        (good_prices[good_index] - good_average) ** 2
      end
      good_deviation  = Math.sqrt(good_distances.last(STAVE).sum.fdiv(STAVE)).round(2)

      good_last_index = good_prices.length - 1
      good_trend      = (good_model[:coef] * good_last_index + good_model[:inter]).round(2)
      good_residuals  = good_prices.each_with_index.drop(STAVE - 1).map do |good_price, good_index|
        good_expected = good_model[:coef] * (good_index + STAVE - 1) + good_model[:inter]
        (good_price - good_expected.round(2)) ** 2
      end
      good_sqrt       = if good_residuals.empty?
        0.0
      else
        Math.sqrt(good_residuals.sum.fdiv(good_residuals.length))
      end

      {
        boll: good_boll,
        mup: (good_boll + good_deviation * 2).round(2),
        mdn: (good_boll - good_deviation * 2).round(2),
        trend: good_trend,
        up1: (good_trend + good_sqrt).round(2),
        dn1: (good_trend - good_sqrt).round(2),
        up2: (good_trend + good_sqrt * 2).round(2),
        dn2: (good_trend - good_sqrt * 2).round(2)
      }
    end

    def _falling_averages?(good_prices)
      lookback = 20
      [5, 10, 20, 40].all? do |window|
        next false if good_prices.length < window + lookback

        current = good_prices.last(window).sum.fdiv(window)
        previous = good_prices[0...-lookback].last(window).sum.fdiv(window)
        current < previous
      end
    end

    def _good_move(good_price, good_days)
      good_move   = good_price.each_cons(good_days).map {
        |good_aver| good_aver.reduce(&:+).fdiv(good_days).round(2)
      }
      good_move
    end

    def _good_aver(good_stock, good_days)
      good_data   = _good_data(good_stock)
      good_price  = good_data.pluck(:price)
      good_aver   = _good_move(good_price, good_days)
      good_start  = good_price.size - good_aver.size
      good_end    = good_price.size - 1
      for good_index in good_start..good_end
        good_data[good_index][:price] = good_aver[good_index - good_start]
      end
      good_data.pluck(:date, :price)
    end

    def _good_dist(good_stock, good_days)
      good_data   = _good_days(good_stock, good_days).pluck(:date, :price)
      good_aver   = _good_aver(good_stock, good_days)
      good_data.each_with_index do |good_data_, good_index|
        _good_data = good_data_[1] - good_aver[good_index][1]
        good_data[good_index][1] = _good_data ** 2
      end
      good_data
    end

    def _good_boll(good_stock, good_days)
      good_dist   = _good_dist(good_stock, good_days)
      good_dist.map! { |good_date, good_price| good_price }
      good_sqrt   = _good_move(good_dist, good_days)
      good_sqrt.each_with_index do |good_data, good_index|
        good_sqrt[good_index] = Math.sqrt(good_data).round(2)
      end
      good_sqrt
    end

    def _good_days(good_stock, good_days)
      good_data   = _good_data(good_stock)
      good_start  = STAVE - good_days
      good_end    = good_data.size - 1
      good_data   = good_data.slice(good_start, good_end - good_start + 1)
      good_data
    end

    def _good_stave(good_stock)
      good_data   = _good_data(good_stock)
      good_start  = STAVE - 1
      good_end    = good_data.size - 1
      good_data   = good_data.slice(good_start, good_end - good_start + 1)
      good_data
    end

    def _good_stock(good_file, good_index)
      _good_record(good_file.read(32), 0, good_index)
    end

    def _good_record(good_binary, good_offset, good_index)
      good_values = good_binary.unpack("L<5", offset: good_offset)
      good_date   = good_values[0]
      good_year   = good_date / 10_000
      good_month  = good_date / 100 % 100
      good_day    = good_date % 100
      good_price  = good_values[4].fdiv(STAVE)
      good_stock  = {
        date:       Date.new(good_year, good_month, good_day),
        price:      good_price,
        index:      good_index
      }
      good_stock
    end

    def _good_data(good_stock)
      good_data = @good_data_cache[good_stock]
      unless good_data
        good_data = _read_good_data(good_stock)
        @good_data_cache[good_stock] = good_data
      end
      good_data.map(&:dup)
    end

    def _read_good_data(good_stock)
      good_path     = _good_path(good_stock)
      return [] unless File.file?(good_path) && File.size(good_path) > @good_days * 32

      File.open(good_path, "rb") do |good_file|
        good_file.seek(-32, IO::SEEK_END)
        good_last = _good_stock(good_file, -1)
        return [] if good_last[:price] > STAVE

        good_file.seek(-@good_days * 32, IO::SEEK_END)
        good_binary = good_file.read(@good_days * 32)
        return Array.new(@good_days) do |good_index|
          _good_record(good_binary, good_index * 32, good_index)
        end
      end
    end

    def _good_model(good_stock)
      good_price, good_date = _good_model_data(good_stock)
      return {} if good_price.empty?
      return {} if good_price.length < 2
      return {} if good_price.uniq.size < 2

      good_index  = (0...good_price.length).to_a
      good_count  = good_index.length
      good_sum_x  = good_index.sum
      good_sum_y  = good_price.sum
      good_sum_xx = good_index.sum { |value| value * value }
      good_sum_xy = good_index.zip(good_price).sum { |x, y| x * y }
      good_div    = good_count * good_sum_xx - good_sum_x * good_sum_x
      return {} if good_div.zero?
      good_coef   = (good_count * good_sum_xy - good_sum_x * good_sum_y).fdiv(good_div)
      return {} unless good_coef.finite?
      return {} if  good_coef < 1.0 / STAVE
      good_inter  = (good_sum_y - good_coef * good_sum_x).fdiv(good_count)
      return {} unless good_inter.finite?
      good_last   = good_price[-1]
      return {} unless good_last.finite?
      good_model  = {
        stock:      good_stock,
        area:       @good_area,
        coef:       good_coef,
        inter:      good_inter,
        price:      good_last,
        date:       good_date
      }
      good_model
    end

    def _good_model_data(good_stock)
      good_path = _good_path(good_stock)
      return [[], nil] unless File.file?(good_path) && File.size(good_path) > @good_days * 32

      File.open(good_path, "rb") do |good_file|
        good_file.seek(-@good_days * 32, IO::SEEK_END)
        good_binary = good_file.read(@good_days * 32)
        good_last_offset = (@good_days - 1) * 32
        good_last = _good_record(good_binary, good_last_offset, -1)
        return [[], nil] if good_last[:price] > STAVE

        good_prices = Array.new(@good_days) do |good_index|
          good_binary.unpack1("L<", offset: good_index * 32 + 16).fdiv(STAVE)
        end
        [good_prices, good_last[:date]]
      end
    end

    def _good_last_date(good_stock)
      good_path = _good_path(good_stock)
      return nil unless File.file?(good_path) && File.size(good_path) >= 32

      File.open(good_path, "rb") do |good_file|
        good_file.seek(-32, IO::SEEK_END)
        _good_stock(good_file, -1)[:date]
      end
    end

    def _good_trend(good_stock)
      good_stave  = _good_stave(good_stock)
      good_model  = _good_model(good_stock)
      return [] if good_model.empty?
      good_stave.each do |good_data|
        good_price = good_model[:coef] * good_data[:index] + good_model[:inter]
        good_data[:price] = good_price.round(2)
      end
      good_stave
    end

    def _good_sqrt(good_stock)
      good_stave  = _good_stave(good_stock)
      good_trend  = _good_trend(good_stock)
      return 0.0 if good_trend.empty?
      good_stave.each_with_index do |good_data, good_index|
        good_price = good_stave[good_index][:price] - good_trend[good_index][:price]
        good_stave[good_index][:price] = good_price ** 2
      end
      good_price  = good_stave.pluck(:price)
      good_sum    = good_price.sum
      good_div    = good_sum / good_trend.size
      good_sqrt   = Math.sqrt(good_div)
      good_sqrt
    end

    def _good_stocks
      good_stocks = []
      good_files  = _good_files
      good_files.each do |good_file|
        good_stock = good_file[0,8]
        good_stocks.push good_stock
      end
      good_stocks
    end

    def _good_files
      Dir.children(_good_base).select do |good_file|
        good_path = _good_path(good_file[0, 8])
        File.file?(good_path) && File.size(good_path) > @good_days * 32
      end
    end

    def _good_path(good_stock)
      good_path   = _good_base + good_stock + ".day"
      good_path
    end

    def _good_base
      File.join(::Stock.data_root, @good_area, "lday") + File::SEPARATOR
    end

  end
end
