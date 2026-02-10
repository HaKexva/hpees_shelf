require "rails_helper"

RSpec.describe "Books", type: :request do
  let(:batch_year) { create(:batch_year) }
  let(:book) { create(:book, batch_year: batch_year) }

  describe "GET /books" do
    it "returns success" do
      get books_url
      expect(response).to have_http_status(:success)
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
            isbn: "9780123456789",
            note: "Test note",
            title: "New Book",
            total: 1,
            volume: 1
          }
        }
      }.to change(Book, :count).by(1)

      expect(response).to redirect_to(book_url(Book.last))
    end
  end

  describe "GET /books/:id" do
    it "returns success" do
      get book_url(book)
      expect(response).to have_http_status(:success)
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
          volume: book.volume
        }
      }
      expect(response).to redirect_to(book_url(book))
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
end
