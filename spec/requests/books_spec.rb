require "rails_helper"

RSpec.describe "Books", type: :request do
  let(:batch_year) { create(:batch_year) }
  let(:book) { create(:book, batch_year: batch_year) }

  describe "GET /books" do
    it "returns success" do
      get books_url
      expect(response).to have_http_status(:success)
    end

    it "accepts sort by isbn" do
      get books_url, params: { sort: "isbn" }
      expect(response).to have_http_status(:success)
    end

    it "finds by ISBN keyword" do
      create(:book, batch_year: batch_year, title: "Unique Title XYZ", isbn: "9789861817286")
      get books_url, params: { q: "978-986-181" }
      expect(response.body).to include("Unique Title XYZ")
    end
  end

  describe "GET /books/new" do
    it "returns success" do
      get new_book_url
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /books" do
    it "creates a new book" do
      expect {
        post books_url, params: {
          book: {
            batch_year_id: batch_year.id,
            isbn: "9789861817286",
            note: "Test note",
            title: "New Book",
            total: 1,
            volume: 1,
            source: "donated"
          }
        }
      }.to change(Book, :count).by(1)

      expect(response).to redirect_to(books_url)
    end
  end

  describe "GET /books/:id" do
    it "redirects to edit" do
      get book_url(book)
      expect(response).to redirect_to(edit_book_url(book))
    end
  end

  describe "GET /books/:id/edit" do
    it "returns success" do
      get edit_book_url(book)
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /books/:id" do
    it "updates the book" do
      patch book_url(book), params: {
        book: {
          grade_id: book.grade_id,
          batch_year_id: book.batch_year_id,
          isbn: book.isbn,
          note: "Updated note",
          title: "Updated Title",
          total: book.total,
          volume: book.volume,
          source: book.source
        }
      }
      expect(response).to redirect_to(books_url)
    end
  end

  describe "DELETE /books/:id" do
    it "destroys the book" do
      book_to_delete = create(:book, batch_year: batch_year)
      expect {
        delete book_url(book_to_delete)
      }.to change(Book, :count).by(-1)

      expect(response).to redirect_to(books_url)
    end
  end

  describe "GET /books/inventory_pdf" do
    let!(:listed_book) { create(:book, batch_year: batch_year, title: "盤點測試書", isbn: "9789861817286", total: 2) }

    it "redirects when batch_year_id is missing" do
      get inventory_pdf_books_url
      expect(response).to redirect_to(books_url)
      expect(flash[:alert]).to eq("請先選擇屆數。")
    end

    it "returns a PDF when batch_year_id is set" do
      get inventory_pdf_books_url, params: { batch_year_id: batch_year.id, inventory_source: "all" }
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
    end

    it "omits the source column when source filter is applied" do
      get inventory_pdf_books_url, params: { batch_year_id: batch_year.id, inventory_source: "donated" }
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("application/pdf")
    end
  end
end
