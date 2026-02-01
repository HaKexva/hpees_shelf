class BooksController < ApplicationController
  before_action :set_book, only: %i[ show edit update destroy ]

  # GET /books or /books.json
  def index
    @books = Book.all
  end

  # GET /books/import
  # POST /books/import
  def import
    @imported_data = []
    @headers = []
    @expected_columns = %w[title isbn total volume note]

    return unless request.post?

    if params[:confirm] == "true" && params[:import_data].present?
      # Confirm import from hidden field data (Base64 encoded JSON)
      require "json"
      require "base64"
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))

      imported_count = 0
      skipped_count = 0
      selected_grade_id = params[:grade_id].presence&.to_i

      import_data.each do |row|
        book_attrs = {
          title: row["title"] || row["Title"],
          isbn: row["isbn"] || row["ISBN"],
          total: (row["total"] || row["Total"]).to_i,
          volume: (row["volume"] || row["Volume"]).to_i,
          note: row["note"] || row["Note"],
          grade_id: selected_grade_id || (row["grade_id"] || row["Grade ID"]).presence&.to_i
        }

        # Skip if duplicate exists (all columns match)
        if Book.exists?(book_attrs)
          skipped_count += 1
        else
          book = Book.new(book_attrs)
          if book.save
            imported_count += 1
          else
            Rails.logger.error "Failed to save book: #{book.errors.full_messages.join(', ')}"
          end
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
        @imported_data = csv.map(&:to_h)

        # Check for column mismatches
        @missing_columns = @expected_columns - @headers.map(&:downcase)
        @extra_columns = @headers.map(&:downcase) - @expected_columns

        # Check for duplicates in database
        @duplicates = []
        @new_books = []
        @imported_data.each_with_index do |row, index|
          book_attrs = {
            title: row["title"] || row["Title"],
            isbn: row["isbn"] || row["ISBN"]
          }
          existing = Book.find_by(title: book_attrs[:title], isbn: book_attrs[:isbn])
          if existing
            @duplicates << { index: index, row: row, existing: existing }
          else
            @new_books << { index: index, row: row }
          end
        end

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
  end

  # GET /books/1/edit
  def edit
  end

  # POST /books or /books.json
  def create
    @book = Book.new(book_params)

    respond_to do |format|
      if @book.save
        format.html { redirect_to @book, notice: "Book was successfully created." }
        format.json { render :show, status: :created, location: @book }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @book.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /books/1 or /books/1.json
  def update
    respond_to do |format|
      if @book.update(book_params)
        format.html { redirect_to @book, notice: "Book was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @book }
      else
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

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_book
      @book = Book.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def book_params
      params.expect(book: [ :title, :isbn, :total, :volume, :note, :grade_id ])
    end
end
