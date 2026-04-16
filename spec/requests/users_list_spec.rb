# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users list filters and redirects", type: :request do
  let(:batch_year) { create(:batch_year) }

  before { login_as(create(:user, :superadmin, batch_year: batch_year)) }

  describe "GET /users" do
    it "includes per-user loan history link in the table" do
      u = create(:user, batch_year: batch_year, name: "TableRowUser")
      get users_url
      expect(response.body).to include(loan_history_path(user_id: u.id))
    end
  end

  describe "GET /users/:id/edit" do
    it "includes link to loan history scoped to this user" do
      u = create(:user, batch_year: batch_year, name: "LoanLinkUser")
      get edit_user_url(u)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(loan_history_path(user_id: u.id))
    end
  end

  describe "POST /users" do
    it "redirects to the list with the same sort and filters as the last index visit (HAK-117)" do
      get users_url, params: { sort: "id_number", q_name: "Needle" }
      expect {
        post users_url, params: {
          user: {
            name: "HAK117 User",
            batch_year_id: batch_year.id,
            admin: false
          }
        }
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(users_url(q_name: "Needle", sort: "id_number"))
    end
  end
end
