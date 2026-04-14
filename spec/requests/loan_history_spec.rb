# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Loan history (dashboard)", type: :request do
  let(:batch_year) { create(:batch_year) }

  before { login_as(create(:user, :admin, batch_year: batch_year)) }

  describe "GET /loan_history" do
    it "lists users as links (no search field)" do
      student = create(:user, batch_year: batch_year, name: "ClickFilter")
      get loan_history_url
      expect(response).to have_http_status(:success)
      expect(response.body).to include(loan_history_path(user_id: student.id))
      expect(response.body).not_to include("data-controller=\"student-search\"")
      expect(response.body).not_to include("搜尋姓名或學號")
    end

    it "shows circulation rows when user_id is set" do
      book = create(:book, batch_year: batch_year, isbn: "9780000000040")
      student = create(:user, batch_year: batch_year, name: "BorrowerLH")
      book.checkout_to_borrower!(student)
      get loan_history_url, params: { user_id: student.id }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(book.title)
      expect(response.body).to include("BorrowerLH")
    end
  end
end
