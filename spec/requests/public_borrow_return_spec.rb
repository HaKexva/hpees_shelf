require "rails_helper"

RSpec.describe "PublicBorrowReturn", type: :request do
  describe "GET /" do
    it "is accessible without login" do
      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("借還書")
    end

    it "wraps borrow success notice with auto-dismiss Stimulus" do
      batch_year = create(:batch_year)
      student = create(:user, batch_year: batch_year, id_number: "123456", seat_number: "1", admin: false)
      create(
        :book,
        batch_year: batch_year,
        title: "HAK115 Borrow Flash",
        isbn: "9789861817286",
        source: :owned_by_library,
        call_number: "12345678",
        status: Book::STATUS_ON_SHELF,
        user_id: nil
      )

      post public_process_isbn_path, params: {
        action_type: "checkout",
        id_number: student.id_number,
        isbn: "978-986-181-7286"
      }
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response).to have_http_status(:success)
      expect(response.body).to include("已登記借閱")
      expect(response.body).to include('data-controller="flash-auto-dismiss"')
      expect(response.body).to include("flash-auto-dismiss-delay-value=\"3000\"")
    end

    it "does not attach auto-dismiss to error alerts" do
      batch_year = create(:batch_year)
      create(
        :book,
        batch_year: batch_year,
        title: "HAK115 Error Path",
        isbn: "9789861817286",
        source: :owned_by_library,
        call_number: "87654321",
        status: Book::STATUS_ON_SHELF,
        user_id: nil
      )

      post public_process_isbn_path, params: {
        action_type: "checkout",
        id_number: "999999",
        isbn: "9789861817286"
      }
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include("找不到此學號的學生")
      expect(response.body).not_to include('data-controller="flash-auto-dismiss"')
    end

    it "allows a second student to check out the same donated title when total is 2" do
      batch_year = create(:batch_year)
      s1 = create(:user, batch_year: batch_year, id_number: "111111", seat_number: "1", admin: false)
      s2 = create(:user, batch_year: batch_year, id_number: "222222", seat_number: "2", admin: false)
      book = create(
        :book,
        batch_year: batch_year,
        title: "Two-copy donated",
        isbn: "9789861817286",
        source: :donated,
        total: 2,
        status: Book::STATUS_ON_SHELF,
        user_id: nil
      )

      post public_process_isbn_path, params: {
        action_type: "checkout",
        id_number: s1.id_number,
        isbn: "978-986-181-7286"
      }
      expect(response).to redirect_to(root_path)
      book.reload
      expect(book.status).to eq(Book::STATUS_BORROWED)
      expect(book.active_loans_count).to eq(1)

      post public_process_isbn_path, params: {
        action_type: "checkout",
        id_number: s2.id_number,
        isbn: "9789861817286"
      }
      expect(response).to redirect_to(root_path)
      book.reload
      expect(book.active_loans_count).to eq(2)
      expect(book.available_copies).to eq(0)
    end
  end
end
