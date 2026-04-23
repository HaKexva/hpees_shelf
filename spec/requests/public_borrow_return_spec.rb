require "rails_helper"

RSpec.describe "PublicBorrowReturn", type: :request do
  describe "GET /" do
    it "redirects logged-out users to login" do
      get root_path
      expect(response).to redirect_to(login_path)
    end

    it "wraps borrow success notice with auto-dismiss Stimulus" do
      batch_year = create(:batch_year)
      admin = create(:user, :admin, batch_year: batch_year)
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

      login_as(admin)
      post process_isbn_path, params: {
        action_type: "checkout",
        user_id: student.id,
        isbn: "978-986-181-7286"
      }
      expect(response).to redirect_to(admin_dashboard_path)
      follow_redirect!
      expect(response).to have_http_status(:success)
      expect(response.body).to include("已登記借閱")
      expect(response.body).to include('data-controller="flash-auto-dismiss"')
      expect(response.body).to include("flash-auto-dismiss-delay-value=\"3000\"")
    end

    it "does not attach auto-dismiss to error alerts" do
      batch_year = create(:batch_year)
      admin = create(:user, :admin, batch_year: batch_year)
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

      login_as(admin)
      post process_isbn_path, params: {
        action_type: "checkout",
        user_id: -1,
        isbn: "9789861817286"
      }
      expect(response).to redirect_to(admin_dashboard_path)
      follow_redirect!
      expect(response.body).to include("找不到借閱人")
      expect(response.body).not_to include('data-controller="flash-auto-dismiss"')
    end

    it "allows a second student to check out the same donated title when total is 2" do
      batch_year = create(:batch_year)
      admin = create(:user, :admin, batch_year: batch_year)
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

      login_as(admin)
      post process_isbn_path, params: {
        action_type: "checkout",
        user_id: s1.id,
        isbn: "978-986-181-7286"
      }
      expect(response).to redirect_to(admin_dashboard_path)
      book.reload
      expect(book.status).to eq(Book::STATUS_BORROWED)
      expect(book.active_loans_count).to eq(1)

      post process_isbn_path, params: {
        action_type: "checkout",
        user_id: s2.id,
        isbn: "9789861817286"
      }
      expect(response).to redirect_to(admin_dashboard_path)
      book.reload
      expect(book.active_loans_count).to eq(2)
      expect(book.available_copies).to eq(0)
    end
  end
end
