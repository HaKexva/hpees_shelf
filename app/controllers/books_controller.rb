class BooksController < ApplicationController
  before_action :set_book, only: %i[ show edit update destroy return_to_library borrow return_shelf ]

  # GET /books or /books.json
  def index
    BatchYear.ensure_office_exists!
    @books = Book.where.not(title: [ nil, "" ]).includes(:batch_year, :borrowers)
    # Default: hide "歸還圖書館" unless status filter is applied
    if params[:status].present?
      @books = @books.where(status: params[:status])
    else
      @books = @books.where.not(status: Book::STATUS_RETURNED_LIBRARY)
    end
    @books = @books.where(source: params[:source]) if params[:source].present?
    @books = @books.where(batch_year_id: params[:batch_year_id]) if params[:batch_year_id].present?
    if params[:q].to_s.strip.present?
      pattern = "%#{Book.sanitize_sql_like(params[:q].strip)}%"
      @books = @books.where("title LIKE ?", pattern)
    end
    @batch_years = BatchYear.by_number_desc
    @filter_batch_year_id = params[:batch_year_id]
    @filter_q = params[:q].to_s.strip.presence
    @filter_source = params[:source].presence
    @filter_status = params[:status].presence
    @invalid_books = @books.select { |b| b.missing_required_fields.any? }
    @books_with_invalid_isbn = @books.select(&:invalid_isbn?)
    @any_library_books_to_return = Book.where(source: :owned_by_library).where.not(status: Book::STATUS_RETURNED_LIBRARY).exists?
    # 借閱超過一天視為失蹤，在頁面上方列出
    @missing_books = Book.where.not(title: [ nil, "" ])
                         .where.not(status: Book::STATUS_RETURNED_LIBRARY)
                         .overdue_as_missing
                         .includes(:batch_year, :borrowers)
                         .order(borrowed_at: :asc)
  end

  # GET /books/import
  # POST /books/import
  def import
    BatchYear.ensure_office_exists!
    @imported_data = []
    @headers = []
    @required_columns = %w[title isbn source]
    @expected_columns = %w[title isbn total volume note source call_number]
    @column_names_zh = {
      "title" => "書名",
      "isbn" => "ISBN",
      "total" => "總數",
      "volume" => "冊數",
      "note" => "備註",
      "source" => "來源",
      "call_number" => "登錄號"
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
      invalid_skipped_count = 0
      duplicate_action = params[:duplicate_action] || "skip"
      selected_duplicates = (params[:selected_duplicates] || []).map(&:to_i)
      batch_year = BatchYear.find_by(id: selected_batch_year_id)

      import_data.each_with_index do |row, index|
        title = _import_row_value(row, "title", "Title", "書名")
        isbn = _import_row_value(row, "isbn", "ISBN", "國際標準書號")

        # Skip invalid rows (only this row skipped; others still import)
        if title.blank? || isbn.blank?
          invalid_skipped_count += 1
          next
        end

        source_raw = _import_row_value(row, "source", "Source", "來源")
        source_key = _normalize_import_source(source_raw)
        total_raw = _import_row_value(row, "total", "Total", "總數")
        total_value = total_raw.present? && total_raw.to_s.strip.present? ? total_raw.to_s.to_i : 1
        total_value = 1 if total_value < 1
        # 圖書館館藏：總數不允許 > 1（避免 CSV 匯入錯誤設定）
        if source_key == "owned_by_library" && total_value > 1
          Rails.logger.warn "Skip library book with total > 1 in import (index #{index}, ISBN #{isbn}, total #{total_value})"
          skipped_count += 1
          next
        end

        book_attrs = {
          title: title,
          isbn: isbn,
          total: total_value,
          volume: _import_row_value(row, "volume", "Volume", "冊數"),
          note: _import_row_value(row, "note", "Note", "備註"),
          source: source_key,
          grade_id: batch_year&.grade_id,
          batch_year_id: selected_batch_year_id
        }
        if source_key == "owned_by_library"
          call_num = _import_row_value(row, "call_number", "登錄號")
          book_attrs[:call_number] = call_num.to_s.strip.presence if call_num.present?
        end
        if source_key == "owned_by_teacher" && source_raw.present?
          teacher_name = _import_teacher_name_from_source(source_raw)
          if teacher_name.present?
            admin_scope = User.active.where(admin: true)
            teacher =
              admin_scope.find_by(name: teacher_name) ||
              admin_scope.find_by(name: "#{teacher_name}老師") ||
              admin_scope.where("name LIKE ?", "%#{teacher_name}%").first
            book_attrs[:user_id] = teacher.id if teacher
          end
        end

        # Duplicate only when title, isbn, source (and for library: call_number) all match; any difference = independent book
        existing = _import_find_existing(row, title, isbn, source_key)
        is_duplicate = existing.present?

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
            # 勾選保留重複書籍：總數加一，不建立新檔案
            existing.update_column(:total, existing.total.to_i + 1)
            imported_count += 1
            next
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
      message += " 已跳過 #{invalid_skipped_count} 筆不符合的資料。" if invalid_skipped_count > 0
      redirect_to books_path, notice: message, status: :see_other
    elsif params[:file].present?
      # Preview uploaded file (parse CSV without gem to avoid load path issues)
      file = params[:file]
      begin
        raw = file.read
        content = _decode_csv_to_utf8_books(raw)
        @headers, rows = _parse_csv(content)
        @imported_data = rows.reject do |row|
          row.values.all? { |v| v.nil? || v.to_s.strip.empty? }
        end

        # Check for column mismatches (match by column name, order does not matter; both English and Chinese headers are accepted)
        headers_downcase = @headers.map { |h| h&.to_s&.strip }
        normalized_headers = headers_downcase.map { |h| _normalize_book_csv_header_value(h) }.compact
        @missing_columns = @required_columns - normalized_headers
        @extra_columns = normalized_headers.compact - @expected_columns

        # Check if required columns exist (title or its aliases)
        has_title_column = normalized_headers.include?("title")
        has_isbn_column = normalized_headers.include?("isbn")

        # When headers are valid: validate each row against import format (title required); invalid rows show "不符合" in the preview status column
        @invalid_row_indices = []
        @imported_data.each_with_index do |row, index|
          title = _import_row_value(row, "title", "Title", "書名")
          isbn = _import_row_value(row, "isbn", "ISBN", "國際標準書號")
          source = _import_row_value(row, "source", "Source", "來源")
          @invalid_row_indices << index if title.blank? || isbn.blank? || source.blank?
        end

        # Only check for duplicates if required columns exist (duplicate = same title, isbn, source, and for library: call_number)
        @duplicates = []
        @new_books = []
        if has_title_column && has_isbn_column
          @imported_data.each_with_index do |row, index|
            title = _import_row_value(row, "title", "Title", "書名")
            isbn = _import_row_value(row, "isbn", "ISBN", "國際標準書號")
            source_raw = _import_row_value(row, "source", "Source", "來源")
            source_key = _normalize_import_source(source_raw)

            next if title.blank?

            existing = _import_find_existing(row, title, isbn, source_key)
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
    redirect_to edit_book_path(@book), status: :see_other
  end

  # GET /books/new
  def new
    BatchYear.ensure_office_exists!
    @book = Book.new
    @batch_years = BatchYear.class_batches_by_number_desc
    @admin_users = User.active.where(admin: true).order(:name)
  end

  # GET /books/1/edit
  def edit
    BatchYear.ensure_office_exists!
    @batch_years = BatchYear.class_batches_by_number_desc
    @admin_users = User.active.where(admin: true).order(:name)
  end

  # POST /books or /books.json
  def create
    @book = Book.new(book_params)
    # Grade is derived from the selected batch_year
    @book.grade_id = @book.batch_year&.grade_id if @book.batch_year_id.present? && @book.grade_id.blank?
    @book.user_id = nil unless @book.owned_by_teacher? || @book.owned_by_library?

    respond_to do |format|
      if @book.save
        format.html { redirect_to books_path, notice: "書籍已建立。", status: :see_other }
        format.json { render :show, status: :created, location: @book }
      else
        BatchYear.ensure_office_exists!
        @batch_years = BatchYear.class_batches_by_number_desc
        @admin_users = User.active.where(admin: true).order(:name)
        flash.now[:alert] = @book.errors.full_messages.join("；")
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @book.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /books/1 or /books/1.json
  def update
    attrs = book_params
    attrs[:user_id] = nil unless attrs[:source].to_s == "owned_by_teacher" || attrs[:source].to_s == "owned_by_library"
    respond_to do |format|
      if @book.update(attrs)
        # When batch_year changes, optionally sync grade (if grade was not changed in the form, derive from batch_year)
        @book.update_column(:grade_id, @book.batch_year&.grade_id) if @book.batch_year_id.present?
        format.html { redirect_to books_path, notice: "書籍已更新。", status: :see_other }
        format.json { render :show, status: :ok, location: @book }
      else
        BatchYear.ensure_office_exists!
        @batch_years = BatchYear.class_batches_by_number_desc
        @admin_users = User.active.where(admin: true).order(:name)
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

  # POST /books/borrow_by_isbn — Borrow by scanned/entered ISBN (借書掃 ISBN)
  def borrow_by_isbn
    isbn = params[:isbn].to_s.strip
    user_id = params[:user_id].presence&.to_i
    user = User.find_by(id: user_id)
    unless user
      redirect_to root_path, alert: "請選擇借閱人。", status: :see_other
      return
    end
    if isbn.blank?
      redirect_to root_path, alert: "請掃描或輸入 ISBN。", status: :see_other
      return
    end
    # 這個舊的借書入口也改成看所有來源；圖書館館藏若總數大於 1，可借到沒有可用冊數為止
    candidates =
      Book.where.not(status: Book::STATUS_RETURNED_LIBRARY)
          .where("TRIM(COALESCE(isbn, '')) = ?", isbn)
          .where.not(title: [ nil, "" ])
          .includes(:batch_year, :borrowers)
          .to_a

    book = candidates.find do |b|
      if b.owned_by_library? && b.effective_total > 1
        b.can_borrow_copy?
      else
        b.status == Book::STATUS_ON_SHELF
      end
    end

    unless book
      alert_msg =
        if candidates.any?
          "找不到架上且符合此 ISBN 的圖書館館藏（可能已無可借冊數）（ISBN：#{isbn}）。"
        else
          "找不到架上且符合此 ISBN 的圖書館館藏（ISBN：#{isbn}）。"
        end
      redirect_to root_path, alert: alert_msg, status: :see_other
      return
    end

    if book.owned_by_library? && book.effective_total > 1
      if book.can_borrow_copy?
        book.circulation_records.create!(user_id: user.id, borrowed_at: Time.current)
        book.update!(status: Book::STATUS_BORROWED, borrowed_at: Time.current)
      else
        redirect_to root_path, alert: "此書已無可借冊數。", status: :see_other
        return
      end
    else
      book.update!(user_id: user.id, status: Book::STATUS_BORROWED, borrowed_at: Time.current)
      book.circulation_records.create!(user_id: user.id, borrowed_at: Time.current)
    end
    redirect_to root_path, notice: "已登記借閱：#{book.title} → #{user.name}。", status: :see_other
  end

  # POST /books/1/borrow — Library book: set borrower (借書)
  def borrow
    unless @book.owned_by_library?
      redirect_to root_path, alert: "僅圖書館館藏可借閱。", status: :see_other
      return
    end
    if @book.owned_by_library? && @book.effective_total > 1
      unless @book.can_borrow_copy?
        redirect_to root_path, alert: "此書已無可借冊數。", status: :see_other
        return
      end
    else
      if @book.status == Book::STATUS_BORROWED
        redirect_to root_path, alert: "此書已借閱中。", status: :see_other
        return
      end
    end
    user_id = params[:user_id].presence&.to_i
    user = User.find_by(id: user_id)
    unless user
      redirect_to root_path, alert: "請選擇借閱人。", status: :see_other
      return
    end
    if @book.owned_by_library? && @book.effective_total > 1
      @book.circulation_records.create!(user_id: user.id, borrowed_at: Time.current)
      @book.update!(status: Book::STATUS_BORROWED, borrowed_at: Time.current)
    else
      @book.update!(user_id: user.id, status: Book::STATUS_BORROWED, borrowed_at: Time.current)
      @book.circulation_records.create!(user_id: user.id, borrowed_at: Time.current)
    end
    redirect_to root_path, notice: "已登記借閱：#{@book.title} → #{user.name}。", status: :see_other
  end

  # POST /books/1/return_shelf — Mark book as returned (還書); supports all sources (library, donated, class, teacher)
  def return_shelf
    if @book.owned_by_library? && @book.effective_total > 1
      # 強制將所有未還的冊數一併標記為已還
      @book.circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
      @book.update!(user_id: nil, status: Book::STATUS_ON_SHELF, borrowed_at: nil)
    else
      @book.circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
      @book.update!(user_id: nil, status: Book::STATUS_ON_SHELF, borrowed_at: nil)
    end
    redirect_to root_path, notice: "已還書：#{@book.title}。", status: :see_other
  end

  # POST /books/1/return_to_library — Library books: save borrow history then delete the book
  def return_to_library
    if @book.owned_by_library?
      LibraryLoanHistory.create!(
        book_id: @book.id,
        book_title: @book.title.to_s.presence || "（無書名）",
        book_isbn: @book.isbn,
        borrowed_at: @book.borrowed_at,
        returned_at: Time.current,
        batch_year_id: @book.batch_year_id
      )
      @book.circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
      @book.update!(user_id: nil, status: Book::STATUS_RETURNED_LIBRARY, borrowed_at: nil)
      redirect_to books_path, notice: "已歸還圖書館，書籍狀態已標記為「歸還圖書館」，借閱紀錄已保留。", status: :see_other
    else
      redirect_to @book, alert: "僅圖書館的書可執行此操作。", status: :see_other
    end
  end

  # GET /books/return_to_library_batch — Choose which batch's library books to mark as returned (only available in return period; button is hidden otherwise)
  def return_to_library_batch
    return redirect_to books_path, status: :see_other unless Book.show_return_to_library_button?
    @batch_years = BatchYear.class_batches_by_number_desc
  end

  # POST /books/apply_return_to_library_batch — Save borrow history for each library book then delete the books
  def apply_return_to_library_batch
    return redirect_to books_path, status: :see_other unless Book.show_return_to_library_button?
    raw = params[:batch_year_id].to_s
    scope = Book.where(source: :owned_by_library)
    scope = scope.where(batch_year_id: raw.to_i) if raw.present? && raw != "all"

    if raw.blank?
      redirect_to return_to_library_batch_books_path, alert: "請選擇屆數（或全部）。", status: :see_other
      return
    end

    count = 0
    scope.find_each do |book|
      LibraryLoanHistory.transaction do
        LibraryLoanHistory.create!(
          book_id: book.id,
          book_title: book.title.to_s.presence || "（無書名）",
          book_isbn: book.isbn,
          borrowed_at: book.borrowed_at,
          returned_at: Time.current,
          batch_year_id: book.batch_year_id
        )
        book.circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
        book.update!(user_id: nil, status: Book::STATUS_RETURNED_LIBRARY, borrowed_at: nil)
      end
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
    if ids.any?
      now = Time.current
      count = Book.where(id: ids).update_all(deleted_at: now, updated_at: now)
      redirect_to books_path(redirect_params), notice: "已刪除 #{count} 本書籍。", status: :see_other
    else
      redirect_to books_path(redirect_params), alert: "請至少選擇一本書。", status: :see_other
    end
  end

  private
    def _normalize_book_csv_header_value(value)
      s = value.to_s.strip
      return nil if s.blank?

      case s
      when "書名" then "title"
      when "總數" then "total"
      when "冊數" then "volume"
      when "備註" then "note"
      when "國際標準書號" then "isbn"
      when "來源" then "source"
      when "登錄號" then "call_number"
      else s.downcase.presence
      end
    end

    def _decode_csv_to_utf8_books(raw)
      required = @required_columns || %w[title isbn source]
      strip_bom = ->(s) { s.delete_prefix("\uFEFF") }

      header_matches_required = lambda do |decoded|
        header_line = decoded.lines.first.to_s
        headers = _parse_csv_line(header_line)
        normalized = headers.map { |h| _normalize_book_csv_header_value(h) }.compact
        (required - normalized).empty?
      end

      # 1) Prefer real UTF-8 if valid.
      utf8 = raw.dup.force_encoding("UTF-8")
      if utf8.valid_encoding?
        decoded = strip_bom.call(utf8.encode("UTF-8"))
        return decoded if header_matches_required.call(decoded)
      end

      # 2) Try common encodings for Excel/Sheets exports.
      candidates = [
        -> { raw.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("UTF-16BE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("CP950").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("Big5").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") }
      ]

      candidates.each do |decoder|
        begin
          decoded = strip_bom.call(decoder.call)
          return decoded if header_matches_required.call(decoded)
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          next
        end
      end

      # 3) Last resort: UTF-8 with replacement.
      strip_bom.call(raw.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: ""))
    end
    def set_book
      @book = Book.find(params[:id])
    end

    def book_params
      params.require(:book).permit(
        :title,
        :isbn,
        :total,
        :volume,
        :note,
        :source,
        :borrowed_at,
        :edition_part,
        :batch_year_id,
        :grade_id,
        :user_id,
        :call_number
      )
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

    # Map CSV source value (Chinese or English) to Book source enum key; default owned_by_library if blank/unknown
    # For 老師的書: accepts "老師的書" or "XX老師的書" (e.g. 文榛老師的書, Momo老師的書)
    def _normalize_import_source(raw)
      return "owned_by_library" if raw.blank?
      s = raw.to_s.strip
      return "owned_by_library" if s.blank?
      return "owned_by_teacher" if s.end_with?("老師的書")
      # Chinese labels (from zh-TW)
      return "owned_by_library" if s == "圖書館館藏"
      return "donated" if s == "捐贈的書"
      return "owned_by_class" if s == "班級的書"
      # Enum keys (English)
      return s if Book.sources.key?(s)
      "owned_by_library"
    end

    # Extract teacher name from source value like "文榛老師的書" or "Momo老師的書" => "文榛" / "Momo"
    def _import_teacher_name_from_source(raw)
      return nil if raw.blank?
      raw.to_s.strip.sub(/老師的書\z/, "").strip.presence
    end

    # Find existing book that is considered "duplicate": same title, isbn, source; for library also same call_number.
    # Any difference (e.g. different source or call_number) = independent book, returns nil.
    def _import_find_existing(row, title, isbn, source_key)
      scope = Book.where(title: title, isbn: isbn, source: source_key)
      if source_key == "owned_by_library"
        call_num = _import_row_value(row, "call_number", "登錄號")
        scope = scope.where(call_number: call_num.to_s.strip.presence)
      end
      scope.first
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
        when "國際標準書號" then "isbn"
        when "來源" then "source"
        when "登錄號" then "call_number"
        else h_d
        end
      end.compact
      @missing_columns = @required_columns - normalized_headers
      @extra_columns = normalized_headers - @expected_columns
      has_title_column = normalized_headers.include?("title")
      has_isbn_column = normalized_headers.include?("isbn")

      @invalid_row_indices = []
      @imported_data.each_with_index do |row, index|
        title = _import_row_value(row, "title", "Title", "書名")
        isbn = _import_row_value(row, "isbn", "ISBN", "國際標準書號")
        source = _import_row_value(row, "source", "Source", "來源")
        @invalid_row_indices << index if title.blank? || isbn.blank? || source.blank?
      end

      @duplicates = []
      @new_books = []
      if has_title_column && has_isbn_column
        @imported_data.each_with_index do |row, index|
          title = _import_row_value(row, "title", "Title", "書名")
          isbn = _import_row_value(row, "isbn", "ISBN", "國際標準書號")
          source_raw = _import_row_value(row, "source", "Source", "來源")
          source_key = _normalize_import_source(source_raw)
          next if title.blank?
          existing = _import_find_existing(row, title, isbn, source_key)
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
