class UsersController < ApplicationController
  before_action :set_user, only: %i[ show edit update destroy cancel_resignation ]

  # GET /users or /users.json
  def index
    scope = User.includes(:batch_year)
    scope = scope.active unless params[:include_resigned] == "1"
    @users = scope.order(:name)
    @include_resigned = params[:include_resigned] == "1"
    @has_resigned = User.where.not(resigned_at: nil).exists?
  end

  # GET /users/1 or /users/1.json
  def show
  end

  # GET /users/new
  def new
    BatchYear.ensure_office_exists!
    @user = User.new
    @batch_years = BatchYear.by_number_desc
  end

  # GET /users/1/edit
  def edit
    BatchYear.ensure_office_exists!
    @batch_years = BatchYear.by_number_desc
  end

  # POST /users or /users.json
  def create
    attrs = user_params
    _ensure_admin_batch_year(attrs)
    @user = User.new(attrs)

    respond_to do |format|
      if @user.save
        format.html { redirect_to @user, notice: "人員已建立。" }
        format.json { render :show, status: :created, location: @user }
      else
        @batch_years = BatchYear.by_number_desc
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /users/1 or /users/1.json
  def update
    attrs = user_params
    _ensure_admin_batch_year(attrs)
    respond_to do |format|
      if @user.update(attrs)
        format.html { redirect_to @user, notice: "人員已更新。", status: :see_other }
        format.json { render :show, status: :ok, location: @user }
      else
        @batch_years = BatchYear.by_number_desc
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /users/:id/cancel_resignation (HAK-41: only if resigned < 1 month)
  def cancel_resignation
    unless @user.resigned?
      redirect_to @user, alert: "此人員未標記為離職。", status: :see_other
      return
    end
    unless @user.restore_allowed?
      redirect_to @user, alert: "離職超過 1 個月無法復原。", status: :see_other
      return
    end
    @user.update!(resigned_at: nil)
    redirect_to @user, notice: "已取消離職。", status: :see_other
  end

  # DELETE /users/1 or /users/1.json
  def destroy
    @user.destroy!

    respond_to do |format|
      format.html { redirect_to users_path, notice: "人員已刪除。", status: :see_other }
      format.json { head :no_content }
    end
  end

  # DELETE /users/bulk_destroy
  def bulk_destroy
    ids = Array(params[:user_ids]).reject(&:blank?).map(&:to_i)
    if ids.any?
      count = User.where(id: ids).destroy_all.size
      redirect_to users_path, notice: "已刪除 #{count} 位人員。", status: :see_other
    else
      redirect_to users_path, alert: "請至少選擇一位人員。", status: :see_other
    end
  end

  private
    def _ensure_admin_batch_year(attrs)
      return unless attrs[:admin].to_s == "1" || attrs["admin"].to_s == "1"
      return if attrs[:batch_year_id].present? || attrs["batch_year_id"].present?
      ids = attrs[:extra_batch_year_ids].presence || attrs["extra_batch_year_ids"].presence
      first_id = ids.is_a?(Array) ? ids.reject(&:blank?).first : nil
      if first_id.present?
        attrs[:batch_year_id] = first_id
        attrs["batch_year_id"] = first_id
      else
        office = BatchYear.find_by(is_office: true)
        attrs[:batch_year_id] = office&.id
        attrs["batch_year_id"] = office&.id
      end
    end

    def set_user
      @user = User.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def user_params
      params.expect(
        user: [
          :name,
          :id_number,
          :seat_number,
          :admin,
          :batch_year_id,
          { extra_batch_year_ids: [] }
        ]
      )
    end
end
