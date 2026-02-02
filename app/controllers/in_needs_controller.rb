class InNeedsController < ApplicationController
  before_action :set_in_need, only: %i[ show edit update destroy ]

  # GET /in_needs or /in_needs.json
  def index
    @in_needs = InNeed.by_number_desc
  end

  # GET /in_needs/1 or /in_needs/1.json
  def show
    @books = @in_need.books.where.not(title: [ nil, "" ])
  end

  # GET /in_needs/new
  def new
    @in_need = InNeed.new
  end

  # GET /in_needs/1/edit
  def edit
  end

  # POST /in_needs or /in_needs.json
  def create
    @in_need = InNeed.new(in_need_params)

    respond_to do |format|
      if @in_need.save
        format.html { redirect_to @in_need, notice: "屆數已建立。" }
        format.json { render :show, status: :created, location: @in_need }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @in_need.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /in_needs/1 or /in_needs/1.json
  def update
    respond_to do |format|
      if @in_need.update(in_need_params)
        format.html { redirect_to @in_need, notice: "屆數已更新。" }
        format.json { render :show, status: :ok, location: @in_need }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @in_need.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /in_needs/1 or /in_needs/1.json
  def destroy
    @in_need.destroy!

    respond_to do |format|
      format.html { redirect_to in_needs_path, notice: "屆數已刪除。", status: :see_other }
      format.json { head :no_content }
    end
  end

  # DELETE /in_needs/bulk_destroy
  def bulk_destroy
    ids = Array(params[:in_need_ids]).reject(&:blank?).map(&:to_i)
    if ids.any?
      count = InNeed.where(id: ids).destroy_all.size
      redirect_to in_needs_path, notice: "已刪除 #{count} 個屆數。", status: :see_other
    else
      redirect_to in_needs_path, alert: "請至少選擇一個屆數。", status: :see_other
    end
  end

  private
    def set_in_need
      @in_need = InNeed.find(params.expect(:id))
    end

    def in_need_params
      params.expect(in_need: [ :grade_id, :batch_number ])
    end
end
