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
  end

  # GET /books/import
  # POST /books/import
  def import
    BatchYear.ensure_office_exists!
    @imported_data = []
    @headers = []
    @expected_columns = %w[title isbn total volume note source]
    @column_names_zh = {
      "title" => "書名",
      "isbn" => "ISBN",
      "total" => "總數",
      "volume" => "冊數",
      "note" => "備註",
      "source" => "來源"
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

        source_raw = _import_row_value(row, "source", "Source", "來源")
        source_key = _normalize_import_source(source_raw)
        book_attrs = {
          title: title,
          isbn: isbn,
          total: _import_row_value(row, "total", "Total", "總數").to_s.to_i,
          volume: _import_row_value(row, "volume", "Volume", "冊數"),
          note: _import_row_value(row, "note", "Note", "備註"),
          source: source_key,
          grade_id: batch_year&.grade_id,
          batch_year_id: selected_batch_year_id
        }
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
          when "國際標準書號" then "isbn"
          when "來源" then "source"
          else h_d
          end
        end.compact
        @missing_columns = @expected_columns - normalized_headers
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
        format.html { redirect_to edit_book_path(@book), notice: "書籍已建立。" }
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
        format.html { redirect_to edit_book_path(@book), notice: "書籍已更新。", status: :see_other }
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
    # 這個舊的借書入口也改成看所有來源，只要是「架上」狀態即可
    book = Book.where(status: Book::STATUS_ON_SHELF).where("TRIM(COALESCE(isbn, '')) = ?", isbn).first
    unless book
      redirect_to root_path, alert: "找不到架上且符合此 ISBN 的圖書館館藏（ISBN：#{isbn}）。", status: :see_other
      return
    end
    book.update!(user_id: user.id, status: Book::STATUS_BORROWED, borrowed_at: Time.current)
    book.circulation_records.create!(user_id: user.id, borrowed_at: Time.current)
    redirect_to root_path, notice: "已登記借閱：#{book.title} → #{user.name}。", status: :see_other
  end

  # POST /books/1/borrow — Library book: set borrower (借書)
  def borrow
    unless @book.owned_by_library?
      redirect_to root_path, alert: "僅圖書館館藏可借閱。", status: :see_other
      return
    end
    if @book.status == Book::STATUS_BORROWED
      redirect_to root_path, alert: "此書已借閱中。", status: :see_other
      return
    end
    user_id = params[:user_id].presence&.to_i
    user = User.find_by(id: user_id)
    unless user
      redirect_to root_path, alert: "請選擇借閱人。", status: :see_other
      return
    end
    @book.update!(user_id: user.id, status: Book::STATUS_BORROWED, borrowed_at: Time.current)
    @book.circulation_records.create!(user_id: user.id, borrowed_at: Time.current)
    redirect_to root_path, notice: "已登記借閱：#{@book.title} → #{user.name}。", status: :see_other
  end

  # POST /books/1/return_shelf — Library book: clear borrower (還書)
  def return_shelf
    unless @book.owned_by_library?
      redirect_to root_path, alert: "僅圖書館館藏可還書。", status: :see_other
      return
    end
    @book.circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
    @book.update!(user_id: nil, status: Book::STATUS_ON_SHELF, borrowed_at: nil)
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
      count = Book.where(id: ids).destroy_all.size
      redirect_to books_path(redirect_params), notice: "已刪除 #{count} 本書籍。", status: :see_other
    else
      redirect_to books_path(redirect_params), alert: "請至少選擇一本書。", status: :see_other
    end
  end

  private
    def set_book
      @book = Book.find(params.expect(:id))
    end

    def book_params
      params.expect(book: [ :title, :isbn, :total, :volume, :note, :source, :borrowed_at, :edition_part, :batch_year_id, :grade_id, :user_id, :call_number ])
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
        @invalid_row_indices << index if title.blank?
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
