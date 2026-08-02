class StocksController < ApplicationController
  STOCK_ID_PATTERN = /\A(?:(?<area>sz|sh|bj))?(?<code>\d{6})\z/
  STOCK_QUERY_PATTERN = /\A[a-z0-9]{1,8}\z/
  SIGNAL_FILTERS = %w[all buy sell watch].freeze

  # GET /stocks or /stocks.json
  def index
    area    = stock_area
    @area   = area
    stock   = normalized_stock_query
    return render_bad_request if params[:stock].present? && stock.nil?

    encoded_area = STOCK_ID_PATTERN.match(stock.to_s)&.[](:area)
    if encoded_area.present? && encoded_area != area
      return redirect_to stocks_by_area_path(encoded_area, stock: stock, anchor: "current-signals")
    end

    @stock  = stock
    stave   = Stock::Stave.new(area, Stock::STAVE)
    @stocks_stavs, @stavs_date = stave.good_index(stock)
    @signal_filter = normalized_signal_filter
    unless stock
      @signal_counts = signal_group_counts(@stocks_stavs)
      @stocks_stavs = filtered_signals(@stocks_stavs, @signal_filter)
    end
    @buy_candidates = stock ? [] : stave.strongest_buy_candidates
    @result_count = @stocks_stavs.count if stock
    refresh_run = Stock::RefreshRun.new
    @refresh_status = refresh_run.status
    @scheduled_refresh_status = refresh_run.scheduled_status
    @refresh_schedule = Stock::RefreshSchedule.new.status
  end

  def signal_guide
    @area = stock_area
    requested_filter = params[:return_signal].to_s
    @return_signal_filter = requested_filter if requested_filter.in?(SIGNAL_FILTERS) && requested_filter != "all"
  end

  def signal_history
    @area = stock_area
    @performance = Stock::SignalPerformance.new(@area).call
    @history = Stock::AREAS.to_h do |area|
      snapshots = StockSignalSnapshot.where(area: area)
      dates = snapshots.distinct.count(:signal_date)
      [area, {
        rows: snapshots.count,
        stocks: snapshots.distinct.count(:stock),
        dates: dates,
        first_date: snapshots.minimum(:signal_date),
        latest_date: snapshots.maximum(:signal_date),
        ready: dates >= 20
      }]
    end
  end

  def preview_health
    report = Stock::PreviewHealth.new.call
    render json: {
      status: report[:ready] ? "ready" : "incomplete",
      environment: Rails.env,
      log_level: Logger::SEV_LABEL[Rails.logger.level].downcase,
      date: report[:date],
      dates_aligned: report[:dates_aligned],
      markets: report[:markets]
    }, status: report[:ready] ? :ok : :service_unavailable
  end

  # GET /stocks/1 or /stocks/1.json
  def show
    area     = stock_area
    @area    = area
    stock_id = STOCK_ID_PATTERN.match(params[:stock].to_s.downcase)
    return render_not_found unless stock_id

    area    = stock_id[:area] || area
    stock   = "#{area}#{stock_id[:code]}"
    @stock  = stock
    @area   = area
    stave   = Stock::Stave.new(area, Stock::STAVE)
    return render_not_found unless stave.known_stock?(stock)

    @stave_lohas, @stave_years, @bolls_lohas, @bolls_years = stave.good_show(stock)
    @stock_date, @market_date = stave.data_dates(stock)
    @historical_data = @stock_date.present? && @market_date.present? && @stock_date < @market_date
    @signal_timeline = Stock::SignalTimeline.new(area, stock).call
    if @signal_timeline.any?
      current = @signal_timeline.first
      @current_decision = Stock::SignalFamily.classify(current.year_signal, current.lohas_signal)
    end
  end

  private
    def render_bad_request
      if request.format.json?
        render json: { error: "Invalid stock search" }, status: :bad_request
      else
        render :bad_request, status: :bad_request
      end
    end

    def render_not_found
      if request.format.json?
        render json: { error: "Stock not found" }, status: :not_found
      else
        render :not_found, status: :not_found
      end
    end

    def stock_area
      params[:area].to_s.downcase.in?(supported_stock_areas) ? params[:area].downcase : Stock::SZSTK
    end

    def supported_stock_areas
      Stock::AREAS
    end

    def normalized_stock_query
      stock = params[:stock].to_s.strip.downcase
      return nil if stock.empty?
      return stock if STOCK_QUERY_PATTERN.match?(stock)
    end

    def normalized_signal_filter
      params[:signal].to_s.in?(SIGNAL_FILTERS) ? params[:signal].to_s : "all"
    end

    def filtered_signals(scope, filter)
      unless scope.respond_to?(:where)
        return scope if filter == "all"
        return scope.select { |record| signal_group(record) == filter }
      end

      case filter
      when "buy"
        scope.where(years: Stock::SignalFamily::BUY, lohas: Stock::SignalFamily::BUY)
      when "sell"
        scope.where(years: Stock::SignalFamily::SELL).or(scope.where(lohas: Stock::SignalFamily::SELL))
      when "watch"
        scope
          .where.not(years: Stock::SignalFamily::SELL)
          .where.not(lohas: Stock::SignalFamily::SELL)
          .where.not(years: Stock::SignalFamily::BUY, lohas: Stock::SignalFamily::BUY)
      else
        scope
      end
    end

    def signal_group(record)
      Stock::SignalFamily.classify(record.years, record.lohas)
    end

    def signal_group_counts(scope)
      %w[all buy sell watch].to_h do |filter|
        [filter, filtered_signals(scope, filter).count]
      end
    end
  end
