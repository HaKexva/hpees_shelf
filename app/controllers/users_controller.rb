class UsersController < ApplicationController
  before_action :set_user, only: %i[ show edit update destroy cancel_resignation ]

  # GET /users or /users.json — only active (non-resigned) users are shown; resigned users can still log in.
  def index
    @users = filtered_users_scope.includes(:batch_year).order(:name)
    @batch_years = BatchYear.by_number_desc
    @filter_q_name = params[:q_name].to_s.strip.presence
    @filter_q_seat_number = params[:q_seat_number].to_s.strip.presence
    @filter_q_id_number = params[:q_id_number].to_s.strip.presence
    @filter_batch_year_id = params[:batch_year_id].presence
  end

  # GET /users/export — CSV for current list filters (same as index)
  def export
    users = filtered_users_scope.includes(:batch_year).order(:id)
    bom = "\uFEFF"
    headers = %w[姓名 屆數 學號 座號 管理員]
    csv = +""
    csv << bom
    csv << headers.map { |h| _csv_escape(h) }.join(",") << "\n"
    users.find_each do |user|
      row = [
        user.name,
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
      batch_year_id: params[:batch_year_id].presence
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
    @imported_data = []
    @headers = []
    @expected_columns = %w[name]
    @column_names_zh = {
      "name" => "姓名",
      "id_number" => "學號",
      "seat_number" => "座號"
    }

    return unless request.post?

    if params[:export_invalid] == "true" && params[:import_data].present?
      require "json"
      require "base64"
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))

      invalid_rows = []
      import_data.each do |row|
        name = _user_import_value(row, "name", "姓名")
        next unless name.blank?

        invalid_rows << {
          "姓名" => name.presence || "請填寫",
          "學號" => _user_import_value(row, "id_number", "學號").to_s.strip.presence,
          "座號" => _user_import_value(row, "seat_number", "座號").to_s.strip.presence
        }
      end

      headers = %w[姓名 學號 座號]
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
      selected_batch_year_id = params[:batch_year_id].presence&.to_i
      _restore_import_preview_users(import_data, selected_batch_year_id)
      render :import
    elsif params[:confirm] == "true" && params[:import_data].present?
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))

      selected_batch_year_id = params[:batch_year_id].presence&.to_i
      if selected_batch_year_id.blank? || selected_batch_year_id < 1
        _restore_import_preview_users(import_data, params[:batch_year_id].presence&.to_i)
        @batch_years = BatchYear.by_number_desc
        flash.now[:alert] = "請選擇屆數。"
        render :import, status: :unprocessable_entity
        return
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
        name = _user_import_value(row, "name", "姓名")
        if name.blank?
          invalid_skipped_count += 1
          next
        end

        id_number = _user_import_value(row, "id_number", "學號")
        user_attrs = {
          name: name,
          id_number: id_number,
          seat_number: _user_import_value(row, "seat_number", "座號"),
          email: id_number.present? ? "#{id_number}@hpees.tp.edu.tw" : nil,
          batch_year_id: selected_batch_year_id,
          admin: false
        }

        is_duplicate = User.exists?(name: name, id_number: id_number, batch_year_id: selected_batch_year_id)
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
          if failed_examples.size < 5
            failed_examples << "第 #{index + 1} 筆（#{name}）：#{user.errors.full_messages.join('、')}"
          end
          Rails.logger.error "Failed to save user: #{user.errors.full_messages.join(', ')}"
        end
      end

      message = "成功匯入 #{imported_count} 位人員。"
      message += " 已跳過 #{skipped_count} 位重複人員。" if skipped_count > 0
      message += " 已跳過 #{invalid_skipped_count} 筆不符合的資料（缺姓名）。" if invalid_skipped_count > 0
      if failed_count > 0
        message += " 另有 #{failed_count} 位匯入失敗（資料格式不符或缺欄位）。"
        message += " 例：#{failed_examples.join('；')}" if failed_examples.any?
      end
      redirect_to users_path, notice: message, status: :see_other
    elsif params[:file].present?
      file = params[:file]
      begin
        raw = file.read
        content = _decode_csv_to_utf8(raw)
        @headers, rows = _parse_csv_users(content)
        @imported_data = rows.reject { |row| row.values.all? { |v| v.nil? || v.to_s.strip.empty? } }

        headers_stripped = @headers.map { |h| h&.to_s&.strip }
        normalized_headers = headers_stripped.map do |h|
          case h.to_s
          when "姓名" then "name"
          when "學號" then "id_number"
          when "座號" then "seat_number"
          else h.to_s.downcase.presence
          end
        end.compact
        @missing_columns = @expected_columns - normalized_headers
        @extra_columns = normalized_headers - @expected_columns - %w[id_number seat_number]

        @invalid_row_indices = []
        @imported_data.each_with_index do |row, index|
          name = _user_import_value(row, "name", "姓名")
          @invalid_row_indices << index if name.blank?
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
        flash.now[:alert] = "無法解析 CSV：#{e.message}"
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

    def _normalize_user_csv_header_value(value)
      s = value.to_s.strip
      return nil if s.blank?

      case s
      when "姓名" then "name"
      when "學號" then "id_number"
      when "座號" then "seat_number"
      when "管理員" then "admin"
      else s.downcase.presence
      end
    end

    # Try decoding CSV bytes into UTF-8 for both:
    # - Excel exports (Big5/CP950)
    # - Google Sheets exports (UTF-8, sometimes with BOM / sometimes UTF-16)
    def _decode_csv_to_utf8(raw)
      expected = @expected_columns || %w[name]
      strip_bom = ->(s) { s.delete_prefix("\uFEFF") }

      header_matches_expected = lambda do |decoded|
        header_line = decoded.lines.first.to_s
        headers = _parse_csv_line_users(header_line)
        normalized_headers = headers.map { |h| _normalize_user_csv_header_value(h) }.compact
        (expected - normalized_headers).empty?
      end

      # 1) Prefer real UTF-8 if it is valid.
      utf8 = raw.dup.force_encoding("UTF-8")
      if utf8.valid_encoding?
        decoded = strip_bom.call(utf8.encode("UTF-8"))
        return decoded if header_matches_expected.call(decoded)
      end

      # 2) Try common encodings.
      candidates = [
        -> { raw.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("UTF-16BE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("CP950").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("Big5").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") }
      ]

      candidates.each do |decoder|
        begin
          decoded = strip_bom.call(decoder.call)
          return decoded if header_matches_expected.call(decoded)
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          next
        end
      end

      # 3) Last resort: try UTF-8 with replacement, but don't keep ISO-8859-1/CP950 mojibake.
      strip_bom.call(raw.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: ""))
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

    def _restore_import_preview_users(import_data, duplicate_batch_year_id = nil)
      @imported_data = import_data
      @headers = import_data.first&.keys || []
      headers_stripped = @headers.map { |h| h&.to_s&.strip }
      normalized_headers = headers_stripped.map do |h|
        case h.to_s
        when "姓名" then "name"
        when "學號" then "id_number"
        when "座號" then "seat_number"
        else h.to_s.downcase.presence
        end
      end.compact
      @missing_columns = @expected_columns - normalized_headers
      @extra_columns = normalized_headers - @expected_columns - %w[id_number seat_number]
      @invalid_row_indices = []
      @imported_data.each_with_index do |row, index|
        name = _user_import_value(row, "name", "姓名")
        @invalid_row_indices << index if name.blank?
      end
      @preview_batch_year_id = duplicate_batch_year_id
      _compute_import_duplicates_users!(duplicate_batch_year_id)
      @duplicates = []
      @new_users = []
      @imported_data.each_with_index do |row, index|
        @new_users << { index: index, row: row } if _user_import_value(row, "name", "姓名").present?
      end
      @batch_years = BatchYear.by_number_desc
    end

    # Preview-only: after 屆數 is chosen, duplicates in file and vs DB for that batch (different 屆 = different person for same name/id).
    def _compute_import_duplicates_users!(selected_batch_year_id = nil)
      @duplicate_row_indices = []
      @existing_duplicate_row_indices = []
      return if selected_batch_year_id.blank? || selected_batch_year_id.to_i < 1

      keys = @imported_data.map do |row|
        [
          _user_import_value(row, "name", "姓名"),
          _user_import_value(row, "id_number", "學號")
        ]
      end
      key_counts = keys.tally

      @imported_data.each_with_index do |_row, index|
        next if (@invalid_row_indices || []).include?(index)
        name, id_number = keys[index]
        next if name.blank?

        key = [ name, id_number ]
        @duplicate_row_indices << index if key_counts[key].to_i > 1

        @existing_duplicate_row_indices << index if User.exists?(name: name, id_number: id_number, batch_year_id: selected_batch_year_id.to_i)
      end
    end
end
