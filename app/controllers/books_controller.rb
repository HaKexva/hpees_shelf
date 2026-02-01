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
    @expected_columns = %w[title isbn total volume note grade_id]

    return unless request.post?

    if params[:confirm] == "true" && session[:import_data].present?
      # Confirm import from session data
      imported_count = 0
      session[:import_data].each do |row|
        book = Book.new(
          title: row["title"] || row["Title"],
          isbn: row["isbn"] || row["ISBN"],
          total: row["total"] || row["Total"],
          volume: row["volume"] || row["Volume"],
          note: row["note"] || row["Note"],
          grade_id: row["grade_id"] || row["Grade ID"]
        )
        imported_count += 1 if book.save
      end
      session.delete(:import_data)
      session.delete(:import_headers)
      redirect_to books_path, notice: "Successfully imported #{imported_count} books."
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

        # Store in session for confirmation
        session[:import_data] = @imported_data
        session[:import_headers] = @headers

        render :import, status: :unprocessable_entity
      rescue StandardError => e
        flash.now[:alert] = "Error parsing file: #{e.message}"
        render :import, status: :unprocessable_entity
      end
    else
      flash.now[:alert] = "Please select a file to upload."
      render :import, status: :unprocessable_entity
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
