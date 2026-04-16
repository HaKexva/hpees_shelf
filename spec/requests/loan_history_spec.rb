# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Loan history (dashboard)", type: :request do
  let(:batch_year) { create(:batch_year) }

  before { login_as(create(:user, :admin, batch_year: batch_year)) }

  describe "GET /loan_history" do
    it "shows only how to pick a person when no user_id" do
      create(:user, batch_year: batch_year, name: "NotListedHere")
      get loan_history_url
      expect(response).to have_http_status(:success)
      expect(response.body).to include("請從")
      expect(response.body).to include("人員列表")
      expect(response.body).to include("返回人員列表")
      expect(response.body).not_to include("返回借還書")
      expect(response.body).not_to include("NotListedHere")
    end

    it "shows that person's heading and records when user_id is set" do
      book = create(:book, batch_year: batch_year, isbn: "9780000000040")
      student = create(:user, batch_year: batch_year, name: "BorrowerLH")
      book.checkout_to_borrower!(student)
      get loan_history_url, params: { user_id: student.id }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("BorrowerLH")
      expect(response.body).to include("的借閱紀錄")
      expect(response.body).to include(book.title)
    end
  end
end
