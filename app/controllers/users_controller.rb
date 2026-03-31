class UsersController < ApplicationController
  before_action :set_user, only: %i[ show edit update destroy cancel_resignation ]

  # GET /users or /users.json — only active (non-resigned) users are shown; resigned users can still log in.
  def index
    @users = User.active.includes(:batch_year).order(:name)
    @users = @users.where(batch_year_id: params[:batch_year_id]) if params[:batch_year_id].present?
    if params[:q_name].to_s.strip.present?
      pattern = "%#{User.sanitize_sql_like(params[:q_name].strip)}%"
      @users = @users.where("name LIKE :p", p: pattern)
    end
    if params[:q_seat_number].to_s.strip.present?
      pattern = "%#{User.sanitize_sql_like(params[:q_seat_number].strip)}%"
      @users = @users.where("seat_number LIKE :p", p: pattern)
    end
    if params[:q_id_number].to_s.strip.present?
      pattern = "%#{User.sanitize_sql_like(params[:q_id_number].strip)}%"
      @users = @users.where("id_number LIKE :p", p: pattern)
    end
    @batch_years = BatchYear.by_number_desc
    @filter_q_name = params[:q_name].to_s.strip.presence
    @filter_q_seat_number = params[:q_seat_number].to_s.strip.presence
    @filter_q_id_number = params[:q_id_number].to_s.strip.presence
    @filter_batch_year_id = params[:batch_year_id].presence
  end

  # GET /users/1 — redirect to edit (no separate show page)
  def show
    redirect_to edit_user_path(@user), status: :see_other
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
        format.html { redirect_to users_path, notice: "人員已建立。", status: :see_other }
        format.json { render :edit, status: :created, location: @user }
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
        format.html { redirect_to users_path, notice: "人員已更新。", status: :see_other }
        format.json { render :edit, status: :ok, location: @user }
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
      redirect_to edit_user_path(@user), alert: "此人員未標記為離職。", status: :see_other
      return
    end
    unless @user.restore_allowed?
      redirect_to edit_user_path(@user), alert: "離職超過 1 個月無法復原。", status: :see_other
      return
    end
    @user.update!(resigned_at: nil)
    redirect_to edit_user_path(@user), notice: "已取消離職。", status: :see_other
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
    redirect_params = {
      q_name: params[:q_name].presence,
      q_seat_number: params[:q_seat_number].presence,
      q_id_number: params[:q_id_number].presence,
      batch_year_id: params[:batch_year_id].presence
    }.compact
    if ids.any?
      count = User.where(id: ids).destroy_all.size
      redirect_to users_path(redirect_params), notice: "已刪除 #{count} 位人員。", status: :see_other
    else
      redirect_to users_path(redirect_params), alert: "請至少選擇一位人員。", status: :see_other
    end
  end

  # GET /users/import — show form; POST with file — preview; POST with confirm + import_data — perform import
  def import
    BatchYear.ensure_office_exists!
    @imported_data = []
    @headers = []
    @expected_columns = %w[name]
    @column_names_zh = {
      "name" => "姓名",
      "id_number" => "學號",
      "seat_number" => "座號",
      "admin" => "管理員"
    }

    return unless request.post?

    if params[:confirm] == "true" && params[:import_data].present?
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))

      selected_batch_year_id = params[:batch_year_id].presence&.to_i
      if selected_batch_year_id.blank? || selected_batch_year_id < 1
        _restore_import_preview_users(import_data)
        @batch_years = BatchYear.by_number_desc
        flash.now[:alert] = "請選擇屆數。"
        render :import, status: :unprocessable_entity
        return
      end

      imported_count = 0
      skipped_count = 0
      duplicate_action = params[:duplicate_action] || "skip"
      selected_duplicates = (params[:selected_duplicates] || []).map(&:to_i)
      BatchYear.find_by(id: selected_batch_year_id)

      import_data.each_with_index do |row, index|
        name = _user_import_value(row, "name", "姓名")
        next if name.blank?

        id_number = _user_import_value(row, "id_number", "學號")
        user_attrs = {
          name: name,
          id_number: id_number,
          seat_number: _user_import_value(row, "seat_number", "座號"),
          email: id_number.present? ? "#{id_number}@hpees.tp.edu.tw" : nil,
          batch_year_id: selected_batch_year_id,
          admin: _user_import_admin?(row)
        }

        is_duplicate = User.exists?(name: name, batch_year_id: selected_batch_year_id)
        if is_duplicate
          case duplicate_action
          when "skip"
            skipped_count += 1
            next
          when "select"
            unless selected_duplicates.include?(index)
              skipped_count += 1
              next
            end
          end
        end

        user = User.new(user_attrs)
        if user.save
          imported_count += 1
        else
          Rails.logger.error "Failed to save user: #{user.errors.full_messages.join(', ')}"
        end
      end

      message = "成功匯入 #{imported_count} 位人員。"
      message += " 已跳過 #{skipped_count} 位重複人員。" if skipped_count > 0
      redirect_to users_path, notice: message, status: :see_other
    elsif params[:file].present?
      file = params[:file]
      begin
        content = file.read.force_encoding("UTF-8")
        @headers, rows = _parse_csv_users(content)
        @imported_data = rows.reject { |row| row.values.all? { |v| v.nil? || v.to_s.strip.empty? } }

        headers_stripped = @headers.map { |h| h&.to_s&.strip }
        normalized_headers = headers_stripped.map do |h|
          case h.to_s
          when "姓名" then "name"
          when "學號" then "id_number"
          when "座號" then "seat_number"
          when "管理員" then "admin"
          else h.to_s.downcase.presence
          end
        end.compact
        @missing_columns = @expected_columns - normalized_headers
        @extra_columns = normalized_headers - @expected_columns - %w[id_number seat_number admin]

        @invalid_row_indices = []
        names = []
        @imported_data.each_with_index do |row, index|
          name = _user_import_value(row, "name", "姓名")
          names << name
          @invalid_row_indices << index if name.blank?
        end

        # Detect duplicates within this import file by name (for preview only).
        name_counts = names.tally
        @duplicate_row_indices = []
        @imported_data.each_with_index do |row, index|
          next if @invalid_row_indices.include?(index)
          name = names[index]
          next if name.blank?
          @duplicate_row_indices << index if name_counts[name].to_i > 1
        end

        @new_users = []
        if normalized_headers.include?("name")
          @imported_data.each_with_index do |row, index|
            name = _user_import_value(row, "name", "姓名")
            @new_users << { index: index, row: row } if name.present?
          end
        end
      rescue StandardError => e
        flash.now[:alert] = "無法解析 CSV：#{e.message}"
      end
      @batch_years ||= BatchYear.by_number_desc
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

    def _parse_csv_users(content)
      lines = content.split(/\r?\n/)
      return [ [], [] ] if lines.empty?

      headers = _parse_csv_line_users(lines[0])
      rows = lines[1..].filter_map do |line|
        next nil if line.strip.empty?

        values = _parse_csv_line_users(line)
        headers.each_with_index.to_h { |h, i| [ h, values[i] ] }
      end
      [ headers, rows ]
    end

    def _parse_csv_line_users(line)
      fields = []
      i = 0
      while i < line.length
        if line[i] == '"'
          i += 1
          field = +""
          while i < line.length
            if line[i] == '"'
              if line[i + 1] == '"'
                field << '"'
                i += 2
              else
                i += 1
                break
              end
            else
              field << line[i]
              i += 1
            end
          end
          fields << field
        else
          end_idx = line.index(",", i) || line.length
          fields << line[i...end_idx].to_s.strip
          i = end_idx + 1
        end
      end
      fields
    end

    def _user_import_value(row, *keys)
      keys.each do |k|
        v = row[k]
        return v.to_s.strip.presence if v.present? && v.to_s.strip.present?
      end
      nil
    end

    def _user_import_admin?(row)
      v = _user_import_value(row, "admin", "管理員")
      return false if v.blank?

      s = v.to_s.strip
      [ "1", "true", "yes", "y", "是" ].include?(s.downcase) || s == "是"
    end

    def _restore_import_preview_users(import_data)
      @imported_data = import_data
      @headers = import_data.first&.keys || []
      headers_stripped = @headers.map { |h| h&.to_s&.strip }
      normalized_headers = headers_stripped.map do |h|
        case h.to_s
        when "姓名" then "name"
        when "學號" then "id_number"
        when "座號" then "seat_number"
        when "管理員" then "admin"
        else h.to_s.downcase.presence
        end
      end.compact
      @missing_columns = @expected_columns - normalized_headers
      @extra_columns = normalized_headers - @expected_columns - %w[id_number seat_number admin]
      @invalid_row_indices = []
      @imported_data.each_with_index do |row, index|
        name = _user_import_value(row, "name", "姓名")
        @invalid_row_indices << index if name.blank?
      end
      @duplicates = []
      @new_users = []
      @imported_data.each_with_index do |row, index|
        @new_users << { index: index, row: row } if _user_import_value(row, "name", "姓名").present?
      end
      @batch_years = BatchYear.by_number_desc
    end
end
