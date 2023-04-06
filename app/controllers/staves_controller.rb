class StavesController < ApplicationController
  before_action :set_stafe, only: %i[ show edit update destroy ]

  # GET /staves or /staves.json
  def index
    @staves = Stave.all
  end

  # GET /staves/1 or /staves/1.json
  def show
  end

  # GET /staves/new
  def new
    @stafe = Stave.new
  end

  # GET /staves/1/edit
  def edit
  end

  # POST /staves or /staves.json
  def create
    @stafe = Stave.new(stafe_params)

    respond_to do |format|
      if @stafe.save
        format.html { redirect_to stafe_url(@stafe), notice: "Stave was successfully created." }
        format.json { render :show, status: :created, location: @stafe }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @stafe.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /staves/1 or /staves/1.json
  def update
    respond_to do |format|
      if @stafe.update(stafe_params)
        format.html { redirect_to stafe_url(@stafe), notice: "Stave was successfully updated." }
        format.json { render :show, status: :ok, location: @stafe }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @stafe.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /staves/1 or /staves/1.json
  def destroy
    @stafe.destroy

    respond_to do |format|
      format.html { redirect_to staves_url, notice: "Stave was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_stafe
      @stafe = Stave.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def stafe_params
      params.require(:stafe).permit(:stock, :price, :date, :years)
    end
end
