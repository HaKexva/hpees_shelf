class UsersController < ApplicationController
  before_action :set_user, only: %i[ show edit update destroy cancel_resignation ]

  # GET /users or /users.json — only active (non-resigned) users are shown; resigned users can still log in.
  def index
    remember_users_list_query!
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
    users = filtered_users_scope.merge(User.ordered_for_list(sort))
    bom = "\uFEFF"
    headers = %w[姓名 屆數ID 學號 座號 電子信箱 管理員]
    csv = +""
    csv << bom
    csv << headers.map { |h| _csv_escape(h) }.join(",") << "\n"
    users.find_each do |user|
      row = [
        user.name,
        user.batch_year_id.to_s,
        user.admin ? "—" : (user.id_number || ""),
        user.admin ? "—" : (user.seat_number || ""),
        user.email.to_s,
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
        format.html { redirect_to users_path(users_list_query_hash), notice: "人員已建立。", status: :see_other }
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
        format.html { redirect_to users_path(users_list_query_hash), notice: "人員已更新。", status: :see_other }
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
      format.html { redirect_to users_path(users_list_query_hash), notice: "人員已刪除。", status: :see_other }
      format.json { head :no_content }
    end
  end

  # DELETE /users/bulk_destroy
  def bulk_destroy
    ids = Array(params[:user_ids]).reject(&:blank?).map(&:to_i)
    rq = users_bulk_redirect_query
    if ids.any?
      now = Time.current
      count = User.where(id: ids).update_all(deleted_at: now, updated_at: now)
      redirect_to users_path(rq), notice: "已刪除 #{count} 位人員。", status: :see_other
    else
      redirect_to users_path(rq), alert: "請至少選擇一位人員。", status: :see_other
    end
  end

  # GET /users/import — show form; POST with file — preview; POST with confirm + import_data — perform import
  def import
    BatchYear.ensure_office_exists!
    @import_user_preview_ready = false
    @imported_data = []
    @headers = []
    @required_columns = %w[name batch_year_id]
    @expected_columns = %w[name id_number seat_number batch_year_id email admin]
    @column_names_zh = {
      "name" => "姓名",
      "id_number" => "學號",
      "seat_number" => "座號",
      "batch_year_id" => "屆數ID",
      "email" => "電子信箱",
      "admin" => "管理員"
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
          "學號" => _user_import_student_id(row).presence || _user_import_value(row, "id_number", "學號").to_s.strip.presence,
          "座號" => _user_import_seat(row).presence || _user_import_value(row, "seat_number", "座號").to_s.strip.presence,
          "屆數ID" => _user_import_value(row, "batch_year_id", "屆數ID").to_s.strip.presence,
          "電子信箱" => _user_import_value(row, "email", "電子信箱").to_s.strip.presence,
          "管理員" => _user_import_value(row, "admin", "管理員").to_s.strip.presence
        }
      end

      headers = %w[姓名 學號 座號 屆數ID 電子信箱 管理員]
      bom = "\uFEFF"
      csv = +""
      csv << bom
      csv << headers.map { |h| _csv_escape(h) }.join(",") << "\n"
      invalid_rows.each do |r|
        csv << headers.map { |h| _csv_escape(r[h]) }.join(",") << "\n"
      end

      filename = "users_import_invalid_#{Time.zone.now.strftime('%Y%m%d_%H%M')}.csv"
      send_data csv, filename: filename, type: "text/csv; charset=utf-8"
    elsif params[:confirm] == "true" && params[:import_data].present?
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))
      _apply_user_import_row_edits!(import_data, params[:edit_rows])

      imported_count = 0
      skipped_count = 0
      invalid_skipped_count = 0
      failed_count = 0
      failed_examples = []
      duplicate_action = params[:duplicate_action] || "skip"
      selected_duplicates = (params[:selected_duplicates] || []).map(&:to_i)

      import_data.each_with_index do |row, index|
        if _user_import_row_invalid?(row)
          invalid_skipped_count += 1
          next
        end

        effective_batch_year_id = User.import_batch_year_id_from_row(row)
        if effective_batch_year_id.nil? || effective_batch_year_id < 1
          invalid_skipped_count += 1
          next
        end

        name = _user_import_value(row, "name", "姓名")
        id_number = _user_import_student_id(row)
        seat_number = _user_import_seat(row)
        is_admin = User.import_admin_boolean_from_row(row)
        email = _user_import_resolved_email_for_save(row, id_number, is_admin)
        user_attrs = {
          name: name,
          id_number: is_admin ? nil : id_number,
          seat_number: is_admin ? nil : seat_number,
          email: email,
          batch_year_id: effective_batch_year_id,
          admin: is_admin
        }

        is_duplicate = _user_import_row_duplicate_in_database?(row, name, id_number, email, effective_batch_year_id, is_admin)
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
      message += " 已跳過 #{invalid_skipped_count} 筆不符合的資料。" if invalid_skipped_count > 0
      if failed_count > 0
        message += " 另有 #{failed_count} 位匯入失敗（資料格式不符或缺欄位）。"
        message += " 例：#{failed_examples.join('；')}" if failed_examples.any?
      end
      redirect_to users_path(users_list_query_hash), notice: message, status: :see_other
    elsif params[:file].present?
      file = params[:file]
      begin
        @headers, rows = UsersImport::UploadParser.call(file, expected_columns: @required_columns)
        @imported_data = rows.reject { |row| row.values.all? { |v| v.nil? || v.to_s.strip.empty? } }

        headers_stripped = @headers.map { |h| h&.to_s&.strip }
        normalized_headers = headers_stripped.map { |h| _normalize_user_csv_header_value(h) }.compact
        @missing_columns = @required_columns - normalized_headers
        @extra_columns = normalized_headers - @expected_columns

        @invalid_row_indices = []
        @imported_data.each_with_index do |row, index|
          @invalid_row_indices << index if _user_import_row_invalid?(row)
        end
        _rebuild_user_import_preview_flags!

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
      s = value.to_s.strip.delete("\uFEFF")
      return nil if s.blank?

      case s
      when "姓名" then "name"
      when "學號" then "id_number"
      when "座號" then "seat_number"
      when "屆數ID" then "batch_year_id"
      when "電子信箱" then "email"
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

    def _user_import_row_invalid?(row)
      name = _user_import_value(row, "name", "姓名")
      return true if name.blank?

      is_admin = User.import_admin_boolean_from_row(row)
      unless is_admin
        return true unless User.import_student_id_format_ok?(_user_import_first_raw(row, "id_number", "學號"))
        return true unless User.import_seat_format_ok?(_user_import_first_raw(row, "seat_number", "座號"))
      end

      bid = User.import_batch_year_id_from_row(row)
      return true if bid.nil? || bid == -1 || bid < 1

      id_number = _user_import_student_id(row)
      email = _user_import_resolved_email_for_save(row, id_number, is_admin)
      return true if is_admin && email.blank?
      return true if email.present? && !_user_import_email_format_ok?(email)

      false
    end

    def _user_import_resolved_email_for_save(row, id_number, is_admin)
      raw = _user_import_first_raw(row, "email", "電子信箱", "Email")
      unless User.import_user_import_optional_field_blank?(raw)
        v = _user_import_value(row, "email", "電子信箱", "Email")
        return v.to_s.strip.presence
      end
      return nil if is_admin
      return "#{id_number}@hpees.tp.edu.tw" if id_number.present?

      nil
    end

    def _user_import_email_format_ok?(email)
      email.blank? || email.match?(URI::MailTo::EMAIL_REGEXP)
    end

    def _user_import_row_duplicate_in_database?(row, name, id_number, email, batch_year_id, is_admin)
      if is_admin
        e = email.to_s.strip
        return false if e.blank?

        User.where(name: name, batch_year_id: batch_year_id, admin: true)
            .where("LOWER(TRIM(COALESCE(email, ''))) = ?", e.downcase)
            .exists?
      else
        User.exists?(name: name, id_number: id_number, batch_year_id: batch_year_id)
      end
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
        id_number: %w[id_number 學號],
        seat_number: %w[seat_number 座號],
        batch_year_id: %w[batch_year_id 屆數ID],
        email: %w[email Email 電子信箱],
        admin: %w[admin 管理員]
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

    def _user_import_all_non_invalid_have_batch_id?
      return false if @imported_data.blank?

      non_invalid = @imported_data.each_with_index.reject { |_, idx| (@invalid_row_indices || []).include?(idx) }
      return false if non_invalid.empty?

      non_invalid.all? do |row, _|
        bid = User.import_batch_year_id_from_row(row)
        bid.present? && bid >= 1
      end
    end

    def _rebuild_user_import_preview_flags!
      @import_user_preview_ready =
        @missing_columns.blank? &&
        _user_import_all_non_invalid_have_batch_id?

      _compute_import_duplicates_users!
    end

    # Preview: duplicates within file or vs DB use the same (姓名, 學號, 屆數ID) as the row.
    def _compute_import_duplicates_users!
      @duplicate_row_indices = []
      @existing_duplicate_row_indices = []
      return unless @import_user_preview_ready

      key_tally = Hash.new(0)
      @imported_data.each_with_index do |row, index|
        next if (@invalid_row_indices || []).include?(index)

        bid = User.import_batch_year_id_from_row(row)
        next if bid.nil? || bid < 1

        name = _user_import_value(row, "name", "姓名")
        next if name.blank?

        key = _user_import_duplicate_tally_key(row, name, bid)
        next if key.nil?

        key_tally[key] += 1
      end

      @imported_data.each_with_index do |row, index|
        next if (@invalid_row_indices || []).include?(index)

        bid = User.import_batch_year_id_from_row(row)
        next if bid.nil? || bid < 1

        name = _user_import_value(row, "name", "姓名")
        next if name.blank?

        key = _user_import_duplicate_tally_key(row, name, bid)
        next if key.nil?

        is_admin = User.import_admin_boolean_from_row(row)
        id_number = _user_import_student_id(row)
        email = _user_import_resolved_email_for_save(row, id_number, is_admin)

        @duplicate_row_indices << index if key_tally[key] > 1
        @existing_duplicate_row_indices << index if _user_import_row_duplicate_in_database?(row, name, id_number, email, bid, is_admin)
      end
    end

    def _user_import_duplicate_tally_key(row, name, bid)
      is_admin = User.import_admin_boolean_from_row(row)
      if is_admin
        id_number = _user_import_student_id(row)
        email = _user_import_resolved_email_for_save(row, id_number, true)
        return nil if email.blank?

        [ :adm, name, bid, email.to_s.downcase.strip ]
      else
        id_number = _user_import_student_id(row)
        [ :stu, name, bid, id_number ]
      end
    end
end
