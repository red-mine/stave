class StocksController < ApplicationController
  # before_action :set_stock, only: %i[ show edit update destroy ]

  # GET /stocks or /stocks.json
  def index
    stock   = params[:stock]
    area    = unless params[:area].nil? then params[:area] else Stock::SZSTK end
    @stock  = stock
    @area   = area
    stave   = Stock::Stave.new(area, Stock::STAVE)
    @stocks_stavs, @stavs_date = stave.good_index(stock)
  end

  # GET /stocks/1 or /stocks/1.json
  def show
    stock   = params[:stock]
    area    = unless params[:area].nil? then params[:area] else Stock::SZSTK end
    @stock  = stock
    @area   = area
    stave   = Stock::Stave.new(area, Stock::STAVE)
    @stave_lohas, @stave_years, @bolls_lohas, @bolls_years = stave.good_show(stock)
  end

  # GET /stocks/new
  def new
    @stock = Stock.new
  end

  # GET /stocks/1/edit
  def edit
  end

  # POST /stocks or /stocks.json
  def create
    @stock = Stock.new(stock_params)

    respond_to do |format|
      if @stock.save
        format.html { redirect_to stock_url(@stock), notice: "Stock was successfully created." }
        format.json { render :show, status: :created, location: @stock }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @stock.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /stocks/1 or /stocks/1.json
  def update
    respond_to do |format|
      if @stock.update(stock_params)
        format.html { redirect_to stock_url(@stock), notice: "Stock was successfully updated." }
        format.json { render :show, status: :ok, location: @stock }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @stock.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /stocks/1 or /stocks/1.json
  def destroy
    @stock.destroy

    respond_to do |format|
      format.html { redirect_to stocks_url, notice: "Stock was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_stock
      @stock = Stock.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def stock_params
      params.require(:stock).permit(:stock, :price, :date)
    end

  end
