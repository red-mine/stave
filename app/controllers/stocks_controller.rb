class StocksController < ApplicationController
  STOCK_ID_PATTERN = /\A(?:(?<area>sz|sh|bj))?(?<code>\d{6})\z/
  STOCK_QUERY_PATTERN = /\A[a-z0-9]{1,8}\z/

  # GET /stocks or /stocks.json
  def index
    stock   = normalized_stock_query
    return render_bad_request if params[:stock].present? && stock.nil?

    area    = stock_area
    @stock  = stock
    @area   = area
    stave   = Stock::Stave.new(area, Stock::STAVE)
    @stocks_stavs, @stavs_date = stave.good_index(stock)
  end

  # GET /stocks/1 or /stocks/1.json
  def show
    stock_id = STOCK_ID_PATTERN.match(params[:stock].to_s.downcase)
    return render_not_found unless stock_id

    area    = stock_id[:area] || stock_area
    stock   = "#{area}#{stock_id[:code]}"
    @stock  = stock
    @area   = area
    stave   = Stock::Stave.new(area, Stock::STAVE)
    return render_not_found unless stave.known_stock?(stock)

    @stave_lohas, @stave_years, @bolls_lohas, @bolls_years = stave.good_show(stock)
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
  end
