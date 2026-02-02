class BooksController < ApplicationController
  before_action :set_book, only: %i[ show edit update destroy ]

  # GET /books or /books.json
  def index
    # Filter out books with empty title
    @books = Book.where.not(title: [ nil, "" ]).includes(:batch_year)
  end

  # GET /books/import
  # POST /books/import
  def import
    @imported_data = []
    @headers = []
    @expected_columns = %w[title isbn total volume note]
    @column_names_zh = {
      "title" => "書名",
      "isbn" => "ISBN",
      "total" => "總數",
      "volume" => "冊數",
      "note" => "備註"
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
        title = row["title"] || row["Title"]
        isbn = row["isbn"] || row["ISBN"]

        # Skip empty rows
        next if title.blank?

        book_attrs = {
          title: title,
          isbn: isbn,
          total: (row["total"] || row["Total"]).to_i,
          volume: (row["volume"] || row["Volume"]).to_i,
          note: row["note"] || row["Note"],
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

        # Check for column mismatches
        headers_downcase = @headers.map { |h| h&.downcase }
        @missing_columns = @expected_columns - headers_downcase
        @extra_columns = headers_downcase.compact - @expected_columns

        # Check if required columns exist (title or Title)
        has_title_column = headers_downcase.include?("title")
        has_isbn_column = headers_downcase.include?("isbn")

        # Only check for duplicates if required columns exist
        @duplicates = []
        @new_books = []
        if has_title_column && has_isbn_column
          @imported_data.each_with_index do |row, index|
            title = row["title"] || row["Title"]
            isbn = row["isbn"] || row["ISBN"]

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
        flash.now[:alert] = "Error parsing file: #{e.message}"
        render :import
      end
    else
      flash.now[:alert] = "Please select a file to upload."
      render :import
    end
  end

  # GET /books/1 or /books/1.json
  def show
  end

  # GET /books/new
  def new
    @book = Book.new
    @batch_years = BatchYear.by_number_desc
  end

  # GET /books/1/edit
  def edit
    @batch_years = BatchYear.by_number_desc
  end

  # POST /books or /books.json
  def create
    @book = Book.new(book_params)
    # 年級由屆數帶入
    @book.grade_id = @book.batch_year&.grade_id if @book.batch_year_id.present?

    respond_to do |format|
      if @book.save
        format.html { redirect_to @book, notice: "Book was successfully created." }
        format.json { render :show, status: :created, location: @book }
      else
        @batch_years = BatchYear.by_number_desc
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @book.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /books/1 or /books/1.json
  def update
    respond_to do |format|
      if @book.update(book_params)
        # 屆數變更時同步年級（年級為選填，無屆數或屆數無年級時為 nil）
        @book.update_column(:grade_id, @book.batch_year&.grade_id)
        format.html { redirect_to @book, notice: "Book was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @book }
      else
        @batch_years = BatchYear.by_number_desc
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @book.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /books/1 or /books/1.json
  def destroy
    @book.destroy!

    respond_to do |format|
      format.html { redirect_to books_path, notice: "Book was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  # DELETE /books/bulk_destroy
  def bulk_destroy
    ids = Array(params[:book_ids]).reject(&:blank?).map(&:to_i)
    if ids.any?
      count = Book.where(id: ids).destroy_all.size
      redirect_to books_path, notice: "已刪除 #{count} 本書籍。", status: :see_other
    else
      redirect_to books_path, alert: "請至少選擇一本書。", status: :see_other
    end
  end

  private
    def set_book
      @book = Book.find(params.expect(:id))
    end

    def book_params
      params.expect(book: [ :title, :isbn, :total, :volume, :note, :batch_year_id ])
    end

    def _restore_import_preview(import_data)
      @imported_data = import_data
      @headers = import_data.first&.keys || []
      headers_downcase = @headers.map { |h| h&.to_s&.downcase }
      @missing_columns = @expected_columns - headers_downcase
      @extra_columns = headers_downcase.compact - @expected_columns
      has_title_column = headers_downcase.include?("title")
      has_isbn_column = headers_downcase.include?("isbn")
      @duplicates = []
      @new_books = []
      if has_title_column && has_isbn_column
        @imported_data.each_with_index do |row, index|
          title = row["title"] || row["Title"]
          isbn = row["isbn"] || row["ISBN"]
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
