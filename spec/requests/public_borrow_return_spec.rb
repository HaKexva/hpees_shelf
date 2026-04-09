require "rails_helper"

RSpec.describe "PublicBorrowReturn", type: :request do
  describe "GET /" do
    it "is accessible without login" do
      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("借還書")
    end
  end
end
