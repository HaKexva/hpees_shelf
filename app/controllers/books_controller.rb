class BooksController < ApplicationController
  before_action :set_book, only: %i[ show edit update destroy return_to_library ]

  # GET /books or /books.json
  def index
    BatchYear.ensure_office_exists!
    # Filter out books with empty title and those "Returned to library" (hidden after return)
    @books = Book.where.not(title: [ nil, "" ]).where.not(status: Book::STATUS_RETURNED_LIBRARY).includes(:batch_year, :tags)
    @books = @books.where(batch_year_id: params[:batch_year_id]) if params[:batch_year_id].present?
    if params[:q].to_s.strip.present?
      pattern = "%#{Book.sanitize_sql_like(params[:q].strip)}%"
      @books = @books.where("title LIKE ?", pattern)
    end
    if params[:tag].present?
      if params[:tag] == Book::TAG_TEACHER_PREFIX
        @books = if params[:teacher_tag].present?
          @books.tagged_with(params[:teacher_tag])
        else
          @books.tagged_with(ActsAsTaggableOn::Tag.where("name LIKE ?", "%老師的書").pluck(:name), any: true)
        end
      else
        @books = @books.tagged_with(params[:tag])
      end
    end
    @batch_years = BatchYear.by_number_desc
    @has_library_books = Book.tagged_with(Book::TAG_LIBRARY).exists?
    @filter_batch_year_id = params[:batch_year_id]
    @filter_q = params[:q].to_s.strip.presence
    @filter_tag = params[:tag]
    @filter_teacher_tag = params[:teacher_tag]
    teacher_tag_names = ActsAsTaggableOn::Tag.where("name LIKE ?", "%老師的書").pluck(:name).sort
    @teacher_tag_options = teacher_tag_names
    @filter_tag_options = ActsAsTaggableOn::Tag.order(:name).map { |t| [ t.name, t.name ] }
    @invalid_books = @books.select { |b| b.missing_required_fields.any? }
  end

  # GET /books/import
  # POST /books/import
  def import
    BatchYear.ensure_office_exists!
    @imported_data = []
    @headers = []
    @expected_columns = %w[title isbn total volume note tag]
    @column_names_zh = {
      "title" => "書名",
      "isbn" => "ISBN",
      "total" => "總數",
      "volume" => "冊數",
      "note" => "備註",
      "tag" => "標籤"
    }

    return unless request.post?

    if params[:confirm] == "true" && params[:import_data].present?
      # Confirm import from hidden field data (Base64 encoded JSON)
      require "json"
      require "base64"
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))

      selected_batch_year_id = params[:batch_year_id].presence&.to_i
      if selected_batch_year_id.blank? || selected_batch_year_id < 1
        _restore_import_preview(import_data)
        @batch_years = BatchYear.by_number_desc
        flash.now[:alert] = "請選擇屆數。"
        render :import, status: :unprocessable_entity
        return
      end

      imported_count = 0
      skipped_count = 0
      duplicate_action = params[:duplicate_action] || "skip"
      selected_duplicates = (params[:selected_duplicates] || []).map(&:to_i)
      batch_year = BatchYear.find_by(id: selected_batch_year_id)

      import_data.each_with_index do |row, index|
        title = _import_row_value(row, "title", "Title", "書名")
        isbn = _import_row_value(row, "isbn", "ISBN", "國際標準書號")

        # Skip empty rows
        next if title.blank?

        tag_value = _import_row_value(row, "tag", "Tag", "標籤")
        book_attrs = {
          title: title,
          isbn: isbn,
          total: _import_row_value(row, "total", "Total", "總數").to_s.to_i,
          volume: _import_row_value(row, "volume", "Volume", "冊數").to_s.to_i,
          note: _import_row_value(row, "note", "Note", "備註"),
          tag_list: tag_value.present? ? [ tag_value ] : [],
          grade_id: batch_year&.grade_id,
          batch_year_id: selected_batch_year_id
        }

        # Check for duplicate (same title and isbn)
        is_duplicate = Book.exists?(title: title, isbn: isbn)

        if is_duplicate
          case duplicate_action
          when "skip"
            skipped_count += 1
            next
          when "select"
            # Only import if this index was selected
            unless selected_duplicates.include?(index)
              skipped_count += 1
              next
            end
            # "import" - import all duplicates, continue to save
          end
        end

        book = Book.new(book_attrs)
        if book.save
          imported_count += 1
        else
          Rails.logger.error "Failed to save book: #{book.errors.full_messages.join(', ')}"
        end
      end

      message = "成功匯入 #{imported_count} 本書籍。"
      message += " 已跳過 #{skipped_count} 本重複書籍。" if skipped_count > 0
      redirect_to books_path, notice: message, status: :see_other
    elsif params[:file].present?
      # Preview uploaded file (parse CSV without gem to avoid load path issues)
      file = params[:file]
      begin
        content = file.read.force_encoding("UTF-8")
        @headers, rows = _parse_csv(content)
        @imported_data = rows.reject do |row|
          row.values.all? { |v| v.nil? || v.to_s.strip.empty? }
        end

        # Check for column mismatches (match by column name, order does not matter; both English and Chinese headers are accepted)
        headers_downcase = @headers.map { |h| h&.to_s&.strip }
        normalized_headers = headers_downcase.map do |h|
          h_d = h&.downcase
          case h
          when "書名" then "title"
          when "總數" then "total"
          when "冊數" then "volume"
          when "備註" then "note"
          when "標籤" then "tag"
          when "國際標準書號" then "isbn"
          else h_d
          end
        end.compact
        @missing_columns = @expected_columns - normalized_headers
        @extra_columns = normalized_headers.compact - @expected_columns

        # Check if required columns exist (title or its aliases)
        has_title_column = normalized_headers.include?("title")
        has_isbn_column = normalized_headers.include?("isbn")

        # When headers are valid: validate each row against import format (title and tag required); invalid rows show "不符合" in the preview status column
        @invalid_row_indices = []
        @imported_data.each_with_index do |row, index|
          title = _import_row_value(row, "title", "Title", "書名")
          tag = _import_row_value(row, "tag", "Tag", "標籤")
          @invalid_row_indices << index if title.blank? || tag.blank?
        end

        # Only check for duplicates if required columns exist
        @duplicates = []
        @new_books = []
        if has_title_column && has_isbn_column
          @imported_data.each_with_index do |row, index|
            title = _import_row_value(row, "title", "Title", "書名")
            isbn = _import_row_value(row, "isbn", "ISBN", "國際標準書號")

            # Skip rows with empty title
            next if title.blank?

            existing = Book.find_by(title: title, isbn: isbn)
            if existing
              @duplicates << { index: index, row: row, existing: existing }
            else
              @new_books << { index: index, row: row }
            end
          end
        else
          # No duplicate check if columns don't match
          @imported_data.each_with_index do |row, index|
            @new_books << { index: index, row: row }
          end
        end

        @batch_years = BatchYear.by_number_desc
        render :import
      rescue StandardError => e
        flash.now[:alert] = "解析檔案時發生錯誤：#{e.message}"
        render :import
      end
    else
      flash.now[:alert] = "請選擇要上傳的檔案。"
      render :import
    end
  end

  # GET /books/1 or /books/1.json
  def show
  end

  # GET /books/new
  def new
    BatchYear.ensure_office_exists!
    @book = Book.new
    @batch_years = BatchYear.class_batches_by_number_desc
    @admin_users = User.where(admin: true).order(:name)
    @available_tags = ActsAsTaggableOn::Tag.order(:name)
  end

  # GET /books/1/edit
  def edit
    BatchYear.ensure_office_exists!
    @batch_years = BatchYear.class_batches_by_number_desc
    @admin_users = User.where(admin: true).order(:name)
    @available_tags = ActsAsTaggableOn::Tag.order(:name)
  end

  # POST /books or /books.json
  def create
    @book = Book.new(book_params)
    @book.tag_list = build_tag_list_from_params
    # 書來源選「屆數名單」時，以內聯選單選的屆數覆寫 batch_year_id
    _apply_batch_year_from_inline_if_used(@book)
    # Grade is derived from the selected batch_year
    @book.grade_id = @book.batch_year&.grade_id if @book.batch_year_id.present? && @book.grade_id.blank?
    _ensure_required_tag_groups_filled(@book)

    respond_to do |format|
      if @book.errors.empty? && @book.save
        format.html { redirect_to @book, notice: "書籍已建立。" }
        format.json { render :show, status: :created, location: @book }
      else
        BatchYear.ensure_office_exists!
        @batch_years = BatchYear.class_batches_by_number_desc
        @admin_users = User.where(admin: true).order(:name)
        @available_tags = ActsAsTaggableOn::Tag.order(:name)
        flash.now[:alert] = @book.errors.full_messages.join("；")
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @book.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /books/1 or /books/1.json
  def update
    attrs = book_params.except(:source_tag, :tag_list)
    # 圖書館的書在表單選「歸還圖書館」：建立借閱紀錄後刪除書籍（與歸還按鈕同）
    if @book.library_book? && attrs[:status].to_s == Book::STATUS_RETURNED_LIBRARY
      LibraryLoanHistory.create!(
        user_id: @book.user_id,
        book_title: @book.title.to_s.presence || "（無書名）",
        book_isbn: @book.isbn,
        borrowed_at: @book.borrowed_at,
        returned_at: Time.current,
        batch_year_id: @book.batch_year_id
      )
      @book.destroy!
      return redirect_to books_path, notice: "已歸還圖書館並刪除書籍資料，借閱紀錄已保留。", status: :see_other
    end
    @book.assign_attributes(attrs)
    @book.tag_list = build_tag_list_from_params
    _apply_batch_year_from_inline_if_used(@book)
    _ensure_required_tag_groups_filled(@book)
    respond_to do |format|
      if @book.errors.empty? && @book.save
        # When batch_year changes, optionally sync grade (if grade was not changed in the form, derive from batch_year)
        @book.update_column(:grade_id, @book.batch_year&.grade_id) if @book.batch_year_id.present?
        format.html { redirect_to @book, notice: "書籍已更新。", status: :see_other }
        format.json { render :show, status: :ok, location: @book }
      else
        BatchYear.ensure_office_exists!
        @batch_years = BatchYear.class_batches_by_number_desc
        @admin_users = User.where(admin: true).order(:name)
        @available_tags = ActsAsTaggableOn::Tag.order(:name)
        flash.now[:alert] = @book.errors.full_messages.join("；")
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @book.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /books/1 or /books/1.json
  def destroy
    @book.destroy!

    respond_to do |format|
      format.html { redirect_to books_path, notice: "書籍已刪除。", status: :see_other }
      format.json { head :no_content }
    end
  end

  # POST /books/1/return_to_library — Library books: save borrow history then delete the book
  def return_to_library
    if @book.library_book?
      LibraryLoanHistory.create!(
        user_id: @book.user_id,
        book_title: @book.title.to_s.presence || "（無書名）",
        book_isbn: @book.isbn,
        borrowed_at: @book.borrowed_at,
        returned_at: Time.current,
        batch_year_id: @book.batch_year_id
      )
      @book.destroy!
      redirect_to books_path, notice: "已歸還圖書館並刪除書籍資料，借閱紀錄已保留。", status: :see_other
    else
      redirect_to @book, alert: "僅圖書館的書可執行此操作。", status: :see_other
    end
  end

  # GET /books/return_to_library_batch — Choose which batch's library books to mark as returned
  def return_to_library_batch
    return redirect_to books_path, alert: "目前非開放歸還圖書館書籍期間。" unless Book.show_return_to_library_button?
    @batch_years = BatchYear.class_batches_by_number_desc
  end

  # POST /books/apply_return_to_library_batch — Save borrow history for each library book then delete the books
  def apply_return_to_library_batch
    return redirect_to books_path, alert: "目前非開放歸還圖書館書籍期間。" unless Book.show_return_to_library_button?
    raw = params[:batch_year_id].to_s
    scope = Book.tagged_with(Book::TAG_LIBRARY)
    scope = scope.where(batch_year_id: raw.to_i) if raw.present? && raw != "all"

    if raw.blank?
      redirect_to return_to_library_batch_books_path, alert: "請選擇屆數（或全部）。", status: :see_other
      return
    end

    count = 0
    scope.find_each do |book|
      LibraryLoanHistory.create!(
        user_id: book.user_id,
        book_title: book.title.to_s.presence || "（無書名）",
        book_isbn: book.isbn,
        borrowed_at: book.borrowed_at,
        returned_at: Time.current,
        batch_year_id: book.batch_year_id
      )
      book.destroy!
      count += 1
    end

    label = raw == "all" ? "全部屆數" : "該屆"
    redirect_to books_path, notice: "已將#{label} #{count} 本圖書館的書歸還並刪除書籍資料，借閱紀錄已保留。", status: :see_other
  end

  # DELETE /books/bulk_destroy
  def bulk_destroy
    ids = Array(params[:book_ids]).reject(&:blank?).map(&:to_i)
    redirect_params = {}
    redirect_params[:batch_year_id] = params[:batch_year_id] if params[:batch_year_id].present?
    redirect_params[:tag] = params[:tag] if params[:tag].present?
    redirect_params[:teacher_tag] = params[:teacher_tag] if params[:teacher_tag].present?
    if ids.any?
      count = Book.where(id: ids).destroy_all.size
      redirect_to books_path(redirect_params), notice: "已刪除 #{count} 本書籍。", status: :see_other
    else
      redirect_to books_path(redirect_params), alert: "請至少選擇一本書。", status: :see_other
    end
  end

  private
    # 任一组選了「選單來源＝屆數名單」時，用該組內聯選單的屆數覆寫 batch_year_id（多組時最後一組有效）
    def _apply_batch_year_from_inline_if_used(book)
      bp = params[:book] || {}
      # 第一組
      source_tag = bp[:source_tag].to_s.strip
      if source_tag.present? && Book::TagRules.option_source(0, source_tag) == "batch_years"
        by_id = params[:tag_teacher_name].to_s.strip
        book.batch_year_id = by_id if by_id.present? && BatchYear.exists?(by_id)
      end
      # 其餘組 group_1, group_2, ...
      groups = Book::TagRules.groups
      groups.each_with_index do |_g, i|
        next if i == 0
        key = "group_#{i}"
        selected = bp[key].is_a?(Array) ? bp[key].reject(&:blank?).first : bp[key].to_s.strip.presence
        next if selected.blank?
        next unless Book::TagRules.option_source(i, selected) == "batch_years"
        by_id = params["tag_inline_#{i}".to_sym].to_s.strip
        book.batch_year_id = by_id if by_id.present? && BatchYear.exists?(by_id)
      end
    end

    def set_book
      @book = Book.find(params.expect(:id))
    end

    def book_params
      group_keys = (1..9).map { |i| { "group_#{i}" => [] } }
      params.expect(book: [ :title, :isbn, :total, :volume, :note, :source_tag, { tag_list: [] }, :borrowed_at, :edition_part, :batch_year_id, :grade_id, :user_id, :status ] + group_keys)
    end

    def build_tag_list_from_params
      groups = Book::TagRules.groups
      in_group_tags = Book::TagRules.all_tag_names_in_groups
      book_params = params[:book] || {}
      other = Array(book_params[:tag_list]).reject(&:blank?).uniq.reject { |t| in_group_tags.include?(t) }
      list = []
      # 第一組用 source_tag；有內聯輸入時用其值（老師→王老師的書、手動輸入→鍵入內容、屆數名單→由 _apply_batch_year_from_inline_if_used 處理）
      source = book_params[:source_tag].to_s.strip
      inline_val = params[:tag_teacher_name].to_s.strip.presence
      resolved = if source == Book::TAG_TEACHER_PREFIX
        Book.tag_from_teacher_name(inline_val)
      elsif Book::TagRules.option_source(0, source) == "manual" && inline_val.present?
        inline_val
      else
        source
      end
      list << resolved if resolved.present?
      # 其餘組別 group_1, group_2, ...；有內聯時用該組的 tag_inline_i 解析
      groups.each_with_index do |_g, i|
        next if i == 0
        key = "group_#{i}"
        val = book_params[key]
        val = if val.is_a?(Array)
          val.reject(&:blank?).uniq
        elsif val.present?
          [ val.to_s.strip ]
        else
          []
        end
        next if val.empty?
        inline_key = "tag_inline_#{i}".to_sym
        raw_inline = params[inline_key]
        inline_val_i = (raw_inline.is_a?(Array) ? raw_inline.first : raw_inline).to_s.strip.presence
        with_inline = val.select { |t| Book::TagRules.option_popup_prompt(i, t).present? || Book::TagRules.option_source(i, t).present? }
        if with_inline.any?
          resolved_i = _resolve_inline_tag_for_group(i, with_inline.first, inline_val_i)
          list << resolved_i if resolved_i.present?
          list.concat(val - with_inline)
        else
          list.concat(val)
        end
      end
      list.concat(other)
      list.uniq
    end

    # 驗證：所有「必填」的標籤組別都必須有選項；若選到有內聯欄位的選項，內聯欄位也不得為空
    def _ensure_required_tag_groups_filled(book)
      groups = Book::TagRules.groups
      bp = params[:book] || {}

      # 1. 檢查每一組是否有選到任何值（針對 required? 的組別）
      groups.each_with_index do |group, gi|
        next if Book::TagRules.optional?(gi)
        opts = group["options"] || []
        next if opts.empty?

        selected_values =
          if gi == 0
            [ bp[:source_tag].to_s.strip ]
          else
            raw = bp["group_#{gi}"]
            Array(raw).map(&:to_s).map(&:strip)
          end
        selected_values.reject!(&:blank?)
        next if selected_values.any?

        label = group["label"].presence || "組別#{gi + 1}"
        book.errors.add(:base, "「#{label}」為必填，請選擇至少一個標籤。")
      end

      # 2. 若有選到帶內聯欄位的選項，內聯值不得為空
      groups.each_with_index do |group, gi|
        opts = group["options"] || []
        next if opts.empty?

        selected_values =
          if gi == 0
            [ bp[:source_tag].to_s.strip ]
          else
            raw = bp["group_#{gi}"]
            Array(raw).map(&:to_s).map(&:strip)
          end
        selected_values.reject!(&:blank?)
        next if selected_values.empty?

        selected_values.each do |tag_name|
          has_inline = Book::TagRules.option_popup_prompt(gi, tag_name).present? || Book::TagRules.option_source(gi, tag_name).present?
          next unless has_inline

          inline_key = gi == 0 ? :tag_teacher_name : "tag_inline_#{gi}".to_sym
          raw_inline = params[inline_key]
          inline_val = (raw_inline.is_a?(Array) ? raw_inline.first : raw_inline).to_s.strip
          next if inline_val.present?

          label = group["label"].presence || "組別#{gi + 1}"
          inline_label = Book::TagRules.option_popup_prompt(gi, tag_name).presence || tag_name
          book.errors.add(:base, "「#{label}」中的「#{inline_label}」為必填，請填寫後再儲存。")
          break
        end
      end
    end

    def _resolve_inline_tag_for_group(group_index, selected_tag_name, inline_value)
      return selected_tag_name if inline_value.blank?
      src = Book::TagRules.option_source(group_index, selected_tag_name)
      case src
      when "manual"
        inline_value
      when "admins", "users"
        inline_value
      when "batch_years"
        by = BatchYear.find_by(id: inline_value)
        by ? by.display_label_with_grade : inline_value
      else
        inline_value.presence || selected_tag_name
      end
    end

    # Lightweight CSV parser (without the csv gem), returns [headers, rows], where rows is an Array of Hashes
    def _parse_csv(content)
      lines = content.split(/\r?\n/)
      return [ [], [] ] if lines.empty?
      headers = _parse_csv_line(lines[0])
      rows = lines[1..].filter_map do |line|
        next nil if line.strip.empty?
        values = _parse_csv_line(line)
        headers.each_with_index.to_h { |h, i| [ h, values[i] ] }
      end
      [ headers, rows ]
    end

    def _parse_csv_line(line)
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

    # Read a value from an import row by column name, order-independent; supports both English and Chinese headers
    def _import_row_value(row, *keys)
      keys.each do |k|
        v = row[k]
        return v.to_s.strip.presence if v.present? && v.to_s.strip.present?
      end
      nil
    end

    def _restore_import_preview(import_data)
      @imported_data = import_data
      @headers = import_data.first&.keys || []
      headers_stripped = @headers.map { |h| h&.to_s&.strip }
      normalized_headers = headers_stripped.map do |h|
        h_d = h&.downcase
        case h
        when "書名" then "title"
        when "總數" then "total"
        when "冊數" then "volume"
        when "備註" then "note"
        when "標籤" then "tag"
        when "國際標準書號" then "isbn"
        else h_d
        end
      end.compact
      @missing_columns = @expected_columns - normalized_headers
      @extra_columns = normalized_headers - @expected_columns
      has_title_column = normalized_headers.include?("title")
      has_isbn_column = normalized_headers.include?("isbn")

      @invalid_row_indices = []
      @imported_data.each_with_index do |row, index|
        title = _import_row_value(row, "title", "Title", "書名")
        tag = _import_row_value(row, "tag", "Tag", "標籤")
        @invalid_row_indices << index if title.blank? || tag.blank?
      end

      @duplicates = []
      @new_books = []
      if has_title_column && has_isbn_column
        @imported_data.each_with_index do |row, index|
          title = _import_row_value(row, "title", "Title", "書名")
          isbn = _import_row_value(row, "isbn", "ISBN", "國際標準書號")
          next if title.blank?
          existing = Book.find_by(title: title, isbn: isbn)
          if existing
            @duplicates << { index: index, row: row, existing: existing }
          else
            @new_books << { index: index, row: row }
          end
        end
      else
        @imported_data.each_with_index do |row, index|
          @new_books << { index: index, row: row }
        end
      end
    end
end
