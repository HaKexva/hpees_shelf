class BooksController < ApplicationController
  before_action :set_book, only: %i[ show edit update destroy return_to_library ]

  # GET /books or /books.json
  def index
    BatchYear.ensure_office_exists!
    # Filter out books with empty title in normal listing
    @books = Book.where.not(title: [ nil, "" ]).includes(:batch_year)
    @books = @books.where(batch_year_id: params[:batch_year_id]) if params[:batch_year_id].present?
    @batch_years = BatchYear.by_number_desc
    @filter_batch_year_id = params[:batch_year_id]
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

        book_attrs = {
          title: title,
          isbn: isbn,
          total: _import_row_value(row, "total", "Total", "總數").to_s.to_i,
          volume: _import_row_value(row, "volume", "Volume", "冊數").to_s.to_i,
          note: _import_row_value(row, "note", "Note", "備註"),
          tag: _import_row_value(row, "tag", "Tag", "標籤"),
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
      # Preview uploaded file
      file = params[:file]
      begin
        require "csv"
        content = file.read.force_encoding("UTF-8")
        csv = CSV.parse(content, headers: true)
        @headers = csv.headers

        # Filter out empty/blank rows
        @imported_data = csv.map(&:to_h).reject do |row|
          row.values.all? { |v| v.nil? || v.to_s.strip.empty? }
        end

        # Check for column mismatches（依欄位名稱辨識，順序不拘；中英文欄名皆可）
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

        # 標題符合時：逐筆檢查是否符合匯入格式（書名、標籤必填），不符合的列在預覽狀態欄顯示「不符合」
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
  end

  # GET /books/1/edit
  def edit
    BatchYear.ensure_office_exists!
    @batch_years = BatchYear.class_batches_by_number_desc
    @admin_users = User.where(admin: true).order(:name)
  end

  # POST /books or /books.json
  def create
    @book = Book.new(book_params)
    apply_tag_teacher_name!(@book)
    # 年級由屆數帶入
    @book.grade_id = @book.batch_year&.grade_id if @book.batch_year_id.present? && @book.grade_id.blank?

    respond_to do |format|
      if @book.save
        format.html { redirect_to @book, notice: "書籍已建立。" }
        format.json { render :show, status: :created, location: @book }
      else
        BatchYear.ensure_office_exists!
        @batch_years = BatchYear.class_batches_by_number_desc
        @admin_users = User.where(admin: true).order(:name)
        flash.now[:alert] = @book.errors.full_messages.join("；")
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @book.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /books/1 or /books/1.json
  def update
    attrs = book_params
    apply_tag_teacher_name!(attrs)
    respond_to do |format|
      if @book.update(attrs)
        # 屆數變更時可同步年級（若表單未改年級則從屆數帶入）
        @book.update_column(:grade_id, @book.batch_year&.grade_id) if @book.batch_year_id.present?
        format.html { redirect_to @book, notice: "書籍已更新。", status: :see_other }
        format.json { render :show, status: :ok, location: @book }
      else
        BatchYear.ensure_office_exists!
        @batch_years = BatchYear.class_batches_by_number_desc
        @admin_users = User.where(admin: true).order(:name)
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

  # POST /books/1/return_to_library — 圖書館的書：標記為「歸還圖書館」
  def return_to_library
    if @book.library_book?
      @book.update!(status: Book::STATUS_RETURNED_LIBRARY)
      redirect_to @book, notice: "已標記為「歸還圖書館」。", status: :see_other
    else
      redirect_to @book, alert: "僅圖書館的書可執行此操作。", status: :see_other
    end
  end

  # DELETE /books/bulk_destroy
  def bulk_destroy
    ids = Array(params[:book_ids]).reject(&:blank?).map(&:to_i)
    redirect_params = params[:batch_year_id].present? ? { batch_year_id: params[:batch_year_id] } : {}
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
      params.expect(book: [ :title, :isbn, :total, :volume, :note, :tag, :borrowed_at, :edition_part, :batch_year_id, :grade_id ])
    end

    def apply_tag_teacher_name!(book_or_attrs)
      current = book_or_attrs.is_a?(Book) ? book_or_attrs.tag : book_or_attrs[:tag]
      return unless current.to_s == Book::TAG_TEACHER_PREFIX
      name = params[:tag_teacher_name].to_s.strip
      value = Book.tag_from_teacher_name(name)
      if book_or_attrs.is_a?(Book)
        book_or_attrs.tag = value
      else
        book_or_attrs[:tag] = value
      end
    end

    # 依欄位名稱讀取匯入列的值，順序不拘；支援英文與中文欄名
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
