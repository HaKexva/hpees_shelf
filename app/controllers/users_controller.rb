class UsersController < ApplicationController
  before_action :set_user, only: %i[ show edit update destroy cancel_resignation ]

  # GET /users or /users.json — only active (non-resigned) users are shown; resigned users can still log in.
  def index
    @sort = User.list_sort_from_param(params[:sort])
    @users = filtered_users_scope.includes(:batch_year).merge(User.ordered_for_list(@sort))
    @batch_years = BatchYear.by_number_desc
    @filter_q_name = params[:q_name].to_s.strip.presence
    @filter_q_seat_number = params[:q_seat_number].to_s.strip.presence
    @filter_q_id_number = params[:q_id_number].to_s.strip.presence
    @filter_batch_year_id = params[:batch_year_id].presence
  end

  # GET /users/export — CSV for current list filters (same as index)
  def export
    sort = User.list_sort_from_param(params[:sort])
    users = filtered_users_scope.includes(:batch_year).merge(User.ordered_for_list(sort))
    bom = "\uFEFF"
    headers = %w[姓名 屆數ID 屆數 學號 座號 管理員]
    csv = +""
    csv << bom
    csv << headers.map { |h| _csv_escape(h) }.join(",") << "\n"
    users.find_each do |user|
      row = [
        user.name,
        user.batch_year_id.to_s,
        user.batch_year&.display_label_with_grade.to_s,
        user.admin ? "—" : (user.id_number || ""),
        user.admin ? "—" : (user.seat_number || ""),
        user.admin ? "是" : "否"
      ]
      csv << row.map { |c| _csv_escape(c) }.join(",") << "\n"
    end
    filename = "users_export_#{Time.zone.now.strftime('%Y%m%d_%H%M')}.csv"
    send_data csv, filename: filename, type: "text/csv; charset=utf-8"
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
      batch_year_id: params[:batch_year_id].presence,
      sort: params[:sort].presence
    }.compact
    if ids.any?
      now = Time.current
      count = User.where(id: ids).update_all(deleted_at: now, updated_at: now)
      redirect_to users_path(redirect_params), notice: "已刪除 #{count} 位人員。", status: :see_other
    else
      redirect_to users_path(redirect_params), alert: "請至少選擇一位人員。", status: :see_other
    end
  end

  # GET /users/import — show form; POST with file — preview; POST with confirm + import_data — perform import
  def import
    BatchYear.ensure_office_exists!
    @user_import_preview_ready = false
    @imported_data = []
    @headers = []
    @expected_columns = %w[name]
    @column_names_zh = {
      "name" => "姓名",
      "batch_year_id" => "屆數ID",
      "batch_year" => "屆數",
      "id_number" => "學號",
      "seat_number" => "座號"
    }

    return unless request.post?

    if params[:export_invalid] == "true" && params[:import_data].present?
      require "json"
      require "base64"
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))
      _apply_user_import_row_edits!(import_data, params[:edit_rows])

      invalid_rows = []
      import_data.each do |row|
        next unless _user_import_row_invalid?(row)

        name = _user_import_value(row, "name", "姓名")
        invalid_rows << {
          "姓名" => name.presence || "請填寫",
          "屆數ID" => _user_import_value(row, "batch_year_id", "屆數ID").to_s.strip.presence,
          "屆數" => _user_import_value(row, "batch_year", "屆數").to_s.strip.presence,
          "學號" => _user_import_student_id(row).presence || _user_import_value(row, "id_number", "學號").to_s.strip.presence,
          "座號" => _user_import_seat(row).presence || _user_import_value(row, "seat_number", "座號").to_s.strip.presence
        }
      end

      headers = %w[姓名 屆數ID 屆數 學號 座號]
      bom = "\uFEFF"
      csv = +""
      csv << bom
      csv << headers.map { |h| _csv_escape(h) }.join(",") << "\n"
      invalid_rows.each do |r|
        csv << headers.map { |h| _csv_escape(r[h]) }.join(",") << "\n"
      end

      filename = "users_import_invalid_#{Time.zone.now.strftime('%Y%m%d_%H%M')}.csv"
      send_data csv, filename: filename, type: "text/csv; charset=utf-8"
    elsif params[:refresh_preview] == "true" && params[:import_data].present?
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))
      _apply_user_import_row_edits!(import_data, params[:edit_rows])
      selected_batch_year_id = params[:batch_year_id].presence&.to_i
      _restore_import_preview_users(import_data, selected_batch_year_id)
      render :import
    elsif params[:confirm] == "true" && params[:import_data].present?
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))
      _apply_user_import_row_edits!(import_data, params[:edit_rows])

      selected_batch_year_id = params[:batch_year_id].presence&.to_i
      selected_batch_year_id = nil if selected_batch_year_id.blank? || selected_batch_year_id < 1

      if selected_batch_year_id.nil?
        needs_fallback = import_data.each_with_index.any? do |row, _idx|
          next false if _user_import_row_invalid?(row)

          eff = _user_import_batch_year_id_for_row(row, nil)
          eff.nil? || eff < 1
        end
        if needs_fallback
          _restore_import_preview_users(import_data, params[:batch_year_id].presence&.to_i)
          @batch_years = BatchYear.by_number_desc
          flash.now[:alert] = "請選擇屆數，或在檔案中為每一筆提供有效的「屆數ID」或「屆數」。"
          render :import, status: :unprocessable_entity
          return
        end
      end

      imported_count = 0
      skipped_count = 0
      invalid_skipped_count = 0
      failed_count = 0
      failed_examples = []
      duplicate_action = params[:duplicate_action] || "skip"
      selected_duplicates = (params[:selected_duplicates] || []).map(&:to_i)
      BatchYear.find_by(id: selected_batch_year_id)

      import_data.each_with_index do |row, index|
        if _user_import_row_invalid?(row)
          invalid_skipped_count += 1
          next
        end

        name = _user_import_value(row, "name", "姓名")
        id_number = _user_import_student_id(row)
        seat_number = _user_import_seat(row)
        effective_batch_year_id = _user_import_batch_year_id_for_row(row, selected_batch_year_id)
        if effective_batch_year_id.nil? || effective_batch_year_id < 1
          invalid_skipped_count += 1
          next
        end

        user_attrs = {
          name: name,
          id_number: id_number,
          seat_number: seat_number,
          email: id_number.present? ? "#{id_number}@hpees.tp.edu.tw" : nil,
          batch_year_id: effective_batch_year_id,
          admin: false
        }

        is_duplicate = User.exists?(name: name, id_number: id_number, batch_year_id: effective_batch_year_id)
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
          failed_count += 1
          if failed_examples.size < 10
            failed_examples << "第 #{index + 1} 筆（#{name}）：#{user.errors.full_messages.join('、')}"
          end
          Rails.logger.error "Failed to save user: #{user.errors.full_messages.join(', ')}"
        end
      end

      message = "成功匯入 #{imported_count} 位人員。"
      message += " 已跳過 #{skipped_count} 位重複人員。" if skipped_count > 0
      message += " 已跳過 #{invalid_skipped_count} 筆不符合的資料（缺姓名或學號／座號格式不符）。" if invalid_skipped_count > 0
      if failed_count > 0
        message += " 另有 #{failed_count} 位匯入失敗（資料格式不符或缺欄位）。"
        message += " 例：#{failed_examples.join('；')}" if failed_examples.any?
      end
      redirect_to users_path, notice: message, status: :see_other
    elsif params[:file].present?
      file = params[:file]
      begin
        @headers, rows = UsersImport::UploadParser.call(file, expected_columns: @expected_columns)
        @imported_data = rows.reject { |row| row.values.all? { |v| v.nil? || v.to_s.strip.empty? } }

        headers_stripped = @headers.map { |h| h&.to_s&.strip }
        normalized_headers = headers_stripped.map { |h| _normalize_user_csv_header_value(h) }.compact
        @missing_columns = @expected_columns - normalized_headers
        known_optional = @expected_columns + %w[id_number seat_number batch_year_id batch_year admin]
        @extra_columns = normalized_headers - known_optional

        @invalid_row_indices = []
        @imported_data.each_with_index do |row, index|
          @invalid_row_indices << index if _user_import_row_invalid?(row)
        end
        @preview_batch_year_id = nil
        _compute_import_duplicates_users!(nil)

        @new_users = []
        if normalized_headers.include?("name")
          @imported_data.each_with_index do |row, index|
            name = _user_import_value(row, "name", "姓名")
            @new_users << { index: index, row: row } if name.present?
          end
        end
      rescue StandardError => e
        flash.now[:alert] = "無法解析檔案（CSV 或 Excel）：#{e.message}"
      end
      @batch_years ||= BatchYear.by_number_desc
    end
  end

  private
    def filtered_users_scope
      users = User.active
      users = users.where(batch_year_id: params[:batch_year_id]) if params[:batch_year_id].present?
      if params[:q_name].to_s.strip.present?
        pattern = "%#{User.sanitize_sql_like(params[:q_name].strip)}%"
        users = users.where("name LIKE :p", p: pattern)
      end
      if params[:q_seat_number].to_s.strip.present?
        pattern = "%#{User.sanitize_sql_like(params[:q_seat_number].strip)}%"
        users = users.where("seat_number LIKE :p", p: pattern)
      end
      if params[:q_id_number].to_s.strip.present?
        pattern = "%#{User.sanitize_sql_like(params[:q_id_number].strip)}%"
        users = users.where("id_number LIKE :p", p: pattern)
      end
      users
    end

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
        fallback = office&.id || BatchYear.by_number_desc.first&.id
        attrs[:batch_year_id] = fallback
        attrs["batch_year_id"] = fallback
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
          :email,
          :admin,
          :batch_year_id,
          { extra_batch_year_ids: [] }
        ]
      )
    end

    def _normalize_user_csv_header_value(value)
      s = value.to_s.strip
      return nil if s.blank?

      case s
      when "姓名" then "name"
      when "學號" then "id_number"
      when "座號" then "seat_number"
      when "屆數ID" then "batch_year_id"
      when "屆數" then "batch_year"
      when "管理員" then "admin"
      else s.downcase.presence
      end
    end

    def _user_import_value(row, *keys)
      targets = keys.map { |k| _normalize_user_csv_header_value(k) }.compact.uniq

      keys.each do |k|
        v = row[k] || row[k.to_s]
        value_str = v.to_s.strip
        return value_str.presence if value_str.present?
      end

      row.each do |row_key, v|
        normalized_key = _normalize_user_csv_header_value(row_key)
        next if normalized_key.blank?
        next unless targets.include?(normalized_key)

        value_str = v.to_s.strip
        return value_str.presence if value_str.present?
      end

      nil
    end

    def _user_import_first_raw(row, *keys)
      targets = keys.map { |k| _normalize_user_csv_header_value(k) }.compact.uniq

      keys.each do |k|
        v = row[k] || row[k.to_s]
        next if v.nil?
        next if v.respond_to?(:blank?) && v.blank? && !v.is_a?(Numeric)

        return v if v.is_a?(Numeric) || v.to_s.strip.present?
      end

      row.each do |row_key, v|
        normalized_key = _normalize_user_csv_header_value(row_key)
        next if normalized_key.blank?
        next unless targets.include?(normalized_key)
        next if v.nil?
        next if v.respond_to?(:blank?) && v.blank? && !v.is_a?(Numeric)

        return v if v.is_a?(Numeric) || v.to_s.strip.present?
      end
      nil
    end

    def _user_import_student_id(row)
      User.import_cell_student_id_digits(_user_import_first_raw(row, "id_number", "學號")).presence
    end

    def _user_import_seat(row)
      User.import_cell_seat_digits(_user_import_first_raw(row, "seat_number", "座號")).presence
    end

    def _user_import_batch_year_id_for_row(row, fallback_id)
      id_raw = _user_import_value(row, "batch_year_id", "屆數ID")
      if id_raw.present?
        stripped = id_raw.to_s.strip
        if stripped.match?(/\A\d+\z/)
          i = stripped.to_i
          return i if i.positive? && BatchYear.exists?(id: i)

          return -1
        end

        return -1
      end

      lab = _user_import_value(row, "batch_year", "屆數")
      if lab.present?
        bid = BatchYear.find_id_from_import_label(lab)
        return bid if bid.present?

        return -1
      end

      fb = fallback_id.to_i
      fb.positive? ? fb : nil
    end

    def _user_import_row_invalid?(row)
      name = _user_import_value(row, "name", "姓名")
      return true if name.blank?

      return true if _user_import_batch_year_id_for_row(row, nil) == -1

      !User.import_student_id_format_ok?(_user_import_first_raw(row, "id_number", "學號")) ||
        !User.import_seat_format_ok?(_user_import_first_raw(row, "seat_number", "座號"))
    end

    def _apply_user_import_row_edits!(import_data, edit_rows_param)
      return if import_data.blank? || edit_rows_param.blank?

      edit_rows =
        if edit_rows_param.respond_to?(:to_unsafe_h)
          edit_rows_param.to_unsafe_h
        else
          edit_rows_param.to_h
        end

      import_data.each_with_index do |row, idx|
        edits = edit_rows[idx.to_s] || edit_rows[idx]
        next if edits.blank?

        _apply_one_user_import_row_edit!(row, edits.to_h)
      end
    end

    def _apply_one_user_import_row_edit!(row, edits)
      return if row.blank? || edits.blank?

      map = {
        name: %w[name Name 姓名],
        batch_year_id: %w[batch_year_id 屆數ID],
        batch_year: %w[batch_year 屆數],
        id_number: %w[id_number 學號],
        seat_number: %w[seat_number 座號]
      }

      map.each do |field, keys|
        next unless edits.key?(field.to_s)

        v = edits[field.to_s].to_s.strip

        if v.blank?
          k = keys.find { |kk| row.key?(kk) } || keys.first
          row[k] = ""
          next
        end

        k = keys.find { |kk| row.key?(kk) } || keys.first
        row[k] = v
      end
    end

    def _restore_import_preview_users(import_data, duplicate_batch_year_id = nil)
      @imported_data = import_data
      @headers = import_data.first&.keys || []
      headers_stripped = @headers.map { |h| h&.to_s&.strip }
      normalized_headers = headers_stripped.map { |h| _normalize_user_csv_header_value(h) }.compact
      @missing_columns = @expected_columns - normalized_headers
      known_optional = @expected_columns + %w[id_number seat_number batch_year_id batch_year admin]
      @extra_columns = normalized_headers - known_optional
      @invalid_row_indices = []
      @imported_data.each_with_index do |row, index|
        @invalid_row_indices << index if _user_import_row_invalid?(row)
      end
      @preview_batch_year_id = duplicate_batch_year_id
      _compute_import_duplicates_users!(duplicate_batch_year_id)
      @duplicates = []
      @new_users = []
      @imported_data.each_with_index do |row, index|
        next if (@invalid_row_indices || []).include?(index)

        @new_users << { index: index, row: row } if _user_import_value(row, "name", "姓名").present?
      end
      @batch_years = BatchYear.by_number_desc
    end

    # Preview-only: duplicates in file and vs DB (per-row 屆數／屆數ID when present, else selected 屆數).
    def _compute_import_duplicates_users!(selected_batch_year_id = nil)
      @duplicate_row_indices = []
      @existing_duplicate_row_indices = []
      fallback = selected_batch_year_id.present? && selected_batch_year_id.to_i >= 1 ? selected_batch_year_id.to_i : nil

      keys = @imported_data.map do |row|
        eff = _user_import_batch_year_id_for_row(row, fallback)
        [
          _user_import_value(row, "name", "姓名"),
          _user_import_student_id(row),
          eff
        ]
      end
      key_counts = keys.tally

      @imported_data.each_with_index do |row, index|
        next if (@invalid_row_indices || []).include?(index)
        name = _user_import_value(row, "name", "姓名")
        id_number = _user_import_student_id(row)
        next if name.blank?

        eff = _user_import_batch_year_id_for_row(row, fallback)
        next if eff.nil? || eff < 1

        key = [ name, id_number, eff ]
        @duplicate_row_indices << index if key_counts[key].to_i > 1

        @existing_duplicate_row_indices << index if User.exists?(name: name, id_number: id_number, batch_year_id: eff)
      end

      @user_import_preview_ready =
        @missing_columns.blank? && (fallback.present? || _user_import_all_non_invalid_rows_have_batch?(fallback))
    end

    def _user_import_all_non_invalid_rows_have_batch?(fallback)
      return false if @imported_data.blank?

      @imported_data.each_with_index.all? do |row, idx|
        next true if (@invalid_row_indices || []).include?(idx)

        eff = _user_import_batch_year_id_for_row(row, fallback)
        eff.present? && eff >= 1
      end
    end
end
