require "rails_helper"

RSpec.describe "Books import preview", type: :request do
  let(:batch_year) { create(:batch_year) }

  before { login_as(create(:user, :admin, batch_year: batch_year)) }

  describe "POST /books/import" do
    it "parses UTF-8 CSV without corrupting Chinese text" do
      post import_books_path, params: {
        file: fixture_file_upload("books_import_utf8.csv", "text/csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("UTF8書")
      expect(response.body).to include("9789861817286")
    end

    it "parses Big5-encoded CSV (common Excel export on Windows)" do
      post import_books_path, params: {
        file: fixture_file_upload("books_import_big5.csv", "text/csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Big5書")
      expect(response.body).to include("9789861817286")
    end

    it "parses legacy .xls via Roo (not CSV text decoding)" do
      post import_books_path, params: {
        file: fixture_file_upload("books_import.xls", "application/vnd.ms-excel")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("XLS書")
      expect(response.body).to include("9789861817286")
    end
  end
end
