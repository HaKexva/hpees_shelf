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

    it "allows editing invalid rows and re-validates on refresh" do
      post import_books_path, params: {
        file: fixture_file_upload("books_import_invalid_isbn.csv", "text/csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("不符合")

      # Apply edits via refresh_preview, using the hidden import_data payload from the first response.
      # The preview form renders import_data in a hidden input; capture it robustly.
      # hidden_field_tag order may vary, so just look for name="import_data" then the first value="...".
      m = response.body.match(/name=(?:"|')import_data(?:"|')[^>]*value=(?:"|')(?<data>[^"']+)(?:"|')/)
      import_data = m && m[:data]
      expect(import_data).to be_present

      post import_books_path, params: {
        refresh_preview: "true",
        import_data: import_data,
        batch_year_id: batch_year.id,
        edit_rows: {
          "0" => {
            "isbn" => "9789861817286"
          }
        }
      }
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("9789861817280")
    end
  end
end
