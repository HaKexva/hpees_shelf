require "csv"

class BooksController < ApplicationController
  before_action :set_book, only: %i[ show edit update destroy ]

  # GET /books or /books.json
  def index
    @books = Book.all
  end

  # GET /books/import
  # POST /books/import
  def import
    if request.post? && params[:file].present?
      file = params[:file]
      @imported_data = []
      @headers = []

      begin
        content = file.read.force_encoding("UTF-8")
        csv = CSV.parse(content, headers: true)
        @headers = csv.headers
        @imported_data = csv.map(&:to_h)

        if params[:confirm] == "true"
          imported_count = 0
          @imported_data.each do |row|
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
          redirect_to books_path, notice: "Successfully imported #{imported_count} books."
          nil
        end
      rescue StandardError => e
        flash.now[:alert] = "Error parsing file: #{e.message}"
        @imported_data = []
      end
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
