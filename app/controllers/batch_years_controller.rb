class BatchYearsController < ApplicationController
  before_action :set_batch_year, only: %i[ show edit update destroy ]

  # GET /batch_years or /batch_years.json
  def index
    @batch_years = BatchYear.by_number_desc
  end

  # GET /batch_years/1 or /batch_years/1.json
  def show
    @books = @batch_year.books.where.not(title: [ nil, "" ])
  end

  # GET /batch_years/new
  def new
    @batch_year = BatchYear.new
  end

  # GET /batch_years/1/edit
  def edit
  end

  # POST /batch_years or /batch_years.json
  def create
    @batch_year = BatchYear.new(batch_year_params)

    respond_to do |format|
      if @batch_year.save
        format.html { redirect_to @batch_year, notice: "屆數已建立。" }
        format.json { render :show, status: :created, location: @batch_year }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @batch_year.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /batch_years/1 or /batch_years/1.json
  def update
    respond_to do |format|
      if @batch_year.update(batch_year_params)
        format.html { redirect_to @batch_year, notice: "屆數已更新。" }
        format.json { render :show, status: :ok, location: @batch_year }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @batch_year.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /batch_years/1 or /batch_years/1.json
  def destroy
    @batch_year.destroy!

    respond_to do |format|
      format.html { redirect_to batch_years_path, notice: "屆數已刪除。", status: :see_other }
      format.json { head :no_content }
    end
  end

  # DELETE /batch_years/bulk_destroy
  def bulk_destroy
    ids = Array(params[:batch_year_ids]).reject(&:blank?).map(&:to_i)
    if ids.any?
      count = BatchYear.where(id: ids).destroy_all.size
      redirect_to batch_years_path, notice: "已刪除 #{count} 個屆數。", status: :see_other
    else
      redirect_to batch_years_path, alert: "請至少選擇一個屆數。", status: :see_other
    end
  end

  private
    def set_batch_year
      @batch_year = BatchYear.find(params.expect(:id))
    end

    def batch_year_params
      params.expect(batch_year: [ :grade_id, :batch_number ])
    end
end
