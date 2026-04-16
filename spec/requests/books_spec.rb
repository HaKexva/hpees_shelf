require "rails_helper"

RSpec.describe "Books", type: :request do
  let(:batch_year) { create(:batch_year) }
  let(:book) { create(:book, batch_year: batch_year) }

  before { login_as(create(:user, :admin, batch_year: batch_year)) }

  describe "GET /books" do
    it "returns success" do
      get books_url
      expect(response).to have_http_status(:success)
    end

    it "includes per-book circulation history link in the table" do
      listed = create(:book, batch_year: batch_year, title: "RowHistBook", isbn: "9780000000040")
      get books_url
      expect(response.body).to include(circulation_history_book_path(listed))
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

    it "shows return-to-library batch link when batch year filter is set and that batch has library books" do
      create(:book, batch_year: batch_year, source: :owned_by_library, call_number: "87654321", title: "LibIdx", isbn: "9780000000026")
      get books_url, params: { batch_year_id: batch_year.id }
      body = response.body
      expect(body).to include("歸還圖書館書籍")
      expect(body).to include("batch_year_id=#{batch_year.id}")
    end

    it "does not show return-to-library batch link without batch year filter" do
      create(:book, batch_year: batch_year, source: :owned_by_library, call_number: "87654321", title: "LibIdx2", isbn: "9780000000033")
      get books_url
      expect(response.body).not_to include("歸還圖書館書籍")
    end

    it "does not show return-to-library batch link when filtered batch has no returnable library books" do
      other = create(:batch_year)
      create(:book, batch_year: batch_year, source: :owned_by_library, call_number: "11111111", isbn: "9780000000040", title: "OnBy")
      get books_url, params: { batch_year_id: other.id }
      expect(response.body).not_to include("歸還圖書館書籍")
    end

    it "includes CSV export link with current filter params" do
      get books_url, params: { source: "donated", q: "Hello", sort: "isbn" }
      expect(response).to have_http_status(:success)
      body = response.body
      expect(body).to include("books/export")
      expect(body).to include("q=Hello")
      expect(body).to include("source=donated")
      expect(body).to include("sort=isbn")
    end

    it "offers class source split by relocation in the source filter" do
      get books_url
      body = response.body
      expect(body).to include(Book::LIST_SOURCE_OWNED_BY_CLASS_STAY)
      expect(body).to include(Book::LIST_SOURCE_OWNED_BY_CLASS_MOVE)
      expect(body).to include("班級的書——留班不動")
      expect(body).to include("班級的書——隨班移動")
    end

    it "filters class books by composite source (班級的書——留班不動 / 隨班移動)" do
      create(:book, batch_year: batch_year, title: "Class Stay Book", source: :owned_by_class, relocation_behavior: :stay, isbn: "9780000000026")
      create(:book, batch_year: batch_year, title: "Class Move Book", source: :owned_by_class, relocation_behavior: :move_with_class, isbn: "9780000000033")

      get books_url, params: { source: Book::LIST_SOURCE_OWNED_BY_CLASS_STAY }
      expect(response.body).to include("Class Stay Book")
      expect(response.body).not_to include("Class Move Book")

      get books_url, params: { source: Book::LIST_SOURCE_OWNED_BY_CLASS_MOVE }
      expect(response.body).to include("Class Move Book")
      expect(response.body).not_to include("Class Stay Book")
    end

    it "lists teacher source options and filters by teachers_all" do
      t1 = create(:user, :admin, batch_year: batch_year, name: "TeacherOne")
      t2 = create(:user, :admin, batch_year: batch_year, name: "TeacherTwo")
      create(:book, batch_year: batch_year, title: "T1 Book", source: :owned_by_teacher, user: t1, isbn: "9780000000002")
      create(:book, batch_year: batch_year, title: "T2 Book", source: :owned_by_teacher, user: t2, isbn: "9780000000019")
      create(:book, batch_year: batch_year, title: "Class Book", source: :owned_by_class, isbn: "9780000000026")

      get books_url
      body = response.body
      expect(body).to include("teachers_all")
      expect(body).to include("teacher:#{t1.id}")
      expect(body).to include("teacher:#{t2.id}")
      expect(body).not_to include('value="owned_by_teacher"')

      get books_url, params: { source: "teachers_all" }
      expect(response.body).to include("T1 Book")
      expect(response.body).to include("T2 Book")
      expect(response.body).not_to include("Class Book")

      get books_url, params: { source: "owned_by_teacher" }
      expect(response.body).to include("T1 Book")
      expect(response.body).to include("T2 Book")
      expect(response.body).not_to include("Class Book")
    end

    it "filters by teacher:<id> to that teacher only" do
      t1 = create(:user, :admin, batch_year: batch_year, name: "FilterT1")
      t2 = create(:user, :admin, batch_year: batch_year, name: "FilterT2")
      create(:book, batch_year: batch_year, title: "Only T1", source: :owned_by_teacher, user: t1, isbn: "9780000000033")
      create(:book, batch_year: batch_year, title: "Only T2", source: :owned_by_teacher, user: t2, isbn: "9780000000040")

      get books_url, params: { source: "teacher:#{t1.id}" }
      expect(response.body).to include("Only T1")
      expect(response.body).not_to include("Only T2")
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

    it "rejects create when 老師的書 is chosen without selecting a teacher" do
      expect {
        post books_url, params: {
          book: {
            batch_year_id: batch_year.id,
            isbn: "9789861817286",
            title: "Teacher book no owner",
            total: 1,
            volume: 1,
            source: "owned_by_teacher",
            user_id: ""
          }
        }
      }.not_to change(Book, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("請選擇老師")
    end

    it "redirects to the list with the same sort and filters as the last index visit (HAK-117)" do
      get books_url, params: { sort: "isbn", source: Book::LIST_SOURCE_OWNED_BY_CLASS_STAY, q: "needle" }
      post books_url, params: {
        book: {
          batch_year_id: batch_year.id,
          isbn: "9789861817286",
          note: "Test note",
          title: "HAK117 New Book",
          total: 1,
          volume: 1,
          source: "donated"
        }
      }
      expect(response).to redirect_to(books_url(q: "needle", source: Book::LIST_SOURCE_OWNED_BY_CLASS_STAY, sort: "isbn"))
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

    it "includes 歸還圖書館 for library books not yet returned to library" do
      lib = create(:book, batch_year: batch_year, source: :owned_by_library, call_number: "87654321", title: "LibEdit", isbn: "9780000000026")
      get edit_book_url(lib)
      expect(response.body).to include("歸還圖書館")
      expect(response.body).to include(return_to_library_book_path(lib))
    end

    it "does not include 歸還圖書館 for non-library books" do
      get edit_book_url(book)
      expect(response.body).not_to include("歸還圖書館")
    end

    it "includes link to circulation history" do
      get edit_book_url(book)
      expect(response.body).to include(circulation_history_book_path(book))
    end
  end

  describe "GET /books/:id/circulation_history" do
    it "returns success and lists circulation rows for the book" do
      student = create(:user, batch_year: batch_year, name: "LoanStudent")
      book.checkout_to_borrower!(student)
      get circulation_history_book_url(book)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("LoanStudent")
      expect(response.body).to include("借出時間")
    end

    it "shows empty state when there are no circulation records" do
      get circulation_history_book_url(book)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("尚無借閱紀錄")
    end

    it "only offers 返回書籍列表 in the header" do
      get circulation_history_book_url(book)
      expect(response.body).to include("返回書籍列表")
      expect(response.body).not_to include("返回編輯")
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

  describe "POST /books/:id/return_to_library and apply_return_to_library_batch (HAK-75)" do
    include ActiveSupport::Testing::TimeHelpers

    let(:lib_book) do
      create(
        :book,
        batch_year: batch_year,
        source: :owned_by_library,
        call_number: "87654321",
        title: "HAK75 Lib Copy",
        isbn: "9780000000095"
      )
    end

    around do |example|
      travel_to(Time.zone.local(2026, 7, 10, 12, 0, 0)) { example.run }
    end

    it "soft-deletes the library book and writes LibraryLoanHistory" do
      expect {
        post return_to_library_book_url(lib_book)
      }.to change(LibraryLoanHistory, :count).by(1)

      expect(response).to redirect_to(books_url)
      saved = Book.unscoped.find(lib_book.id)
      expect(saved.deleted_at).to be_present
      expect(saved.status).to eq(Book::STATUS_RETURNED_LIBRARY)
      expect(Book.find_by(id: lib_book.id)).to be_nil
    end

    it "soft-deletes only scoped library books on batch apply" do
      other_year = create(:batch_year)
      b1 = create(:book, batch_year: batch_year, source: :owned_by_library, call_number: "11111111", isbn: "9780000000026", title: "H75 B1")
      b2 = create(:book, batch_year: batch_year, source: :owned_by_library, call_number: "22222222", isbn: "9780000000033", title: "H75 B2")
      create(:book, batch_year: batch_year, source: :donated, isbn: "9780000000040", title: "H75 Don")
      create(:book, batch_year: other_year, source: :owned_by_library, call_number: "33333333", isbn: "9780000000057", title: "H75 Other")

      expect {
        post apply_return_to_library_batch_books_url, params: { batch_year_id: batch_year.id }
      }.to change(LibraryLoanHistory, :count).by(2)

      expect(Book.unscoped.find(b1.id).deleted_at).to be_present
      expect(Book.unscoped.find(b2.id).deleted_at).to be_present
      expect(Book.find_by(isbn: "9780000000040")).to be_present
      expect(Book.unscoped.find_by(isbn: "9780000000057").deleted_at).to be_nil
    end
  end

  describe "GET /books/export" do
    it "returns CSV rows matching the books list filters (source)" do
      create(:book, batch_year: batch_year, title: "HAK112 Donated Row", source: :donated)
      create(:book, batch_year: batch_year, title: "HAK112 Class Row", source: :owned_by_class)
      get export_books_url, params: { source: "donated" }
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("HAK112 Donated Row")
      expect(response.body).not_to include("HAK112 Class Row")
    end

    it "returns CSV rows matching composite class source (留班不動 / 隨班移動)" do
      create(:book, batch_year: batch_year, title: "Csv Stay", source: :owned_by_class, relocation_behavior: :stay, isbn: "9780000000026")
      create(:book, batch_year: batch_year, title: "Csv Move", source: :owned_by_class, relocation_behavior: :move_with_class, isbn: "9780000000033")
      get export_books_url, params: { source: Book::LIST_SOURCE_OWNED_BY_CLASS_STAY }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Csv Stay")
      expect(response.body).not_to include("Csv Move")
    end

    it "includes only that teacher's rows when source=teacher:<id>" do
      t1 = create(:user, :admin, batch_year: batch_year, name: "CsvT1")
      t2 = create(:user, :admin, batch_year: batch_year, name: "CsvT2")
      create(:book, batch_year: batch_year, title: "Csv Only T1", source: :owned_by_teacher, user: t1, isbn: "9780000000057")
      create(:book, batch_year: batch_year, title: "Csv Only T2", source: :owned_by_teacher, user: t2, isbn: "9780000000064")

      get export_books_url, params: { source: "teacher:#{t1.id}" }
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Csv Only T1")
      expect(response.body).not_to include("Csv Only T2")
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
