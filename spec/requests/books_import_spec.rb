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
            "isbn" => "9789861817286",
            "call_number" => "12345678"
          }
        }
      }
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("9789861817280")
    end

    it "marks 圖書館館藏 rows invalid when 登錄號 is missing (preview matched save rules)" do
      post import_books_path, params: {
        file: fixture_file_upload("books_import_library_no_call_number.csv", "text/csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("缺登錄號")
      expect(response.body).to include("不符合")
    end

    it "confirms import and creates a library book when preview is valid" do
      post import_books_path, params: {
        file: fixture_file_upload("books_import_utf8.csv", "text/csv")
      }
      expect(response).to have_http_status(:success)
      m = response.body.match(/name=(?:"|')import_data(?:"|')[^>]*value=(?:"|')(?<data>[^"']+)(?:"|')/)
      import_data = m && m[:data]
      expect(import_data).to be_present

      post import_books_path, params: {
        refresh_preview: "true",
        import_data: import_data,
        batch_year_id: batch_year.id
      }
      expect(response).to have_http_status(:success)

      m2 = response.body.match(/name=(?:"|')import_data(?:"|')[^>]*value=(?:"|')(?<data>[^"']+)(?:"|')/)
      import_data2 = m2 && m2[:data]
      expect(import_data2).to be_present

      expect {
        post import_books_path, params: {
          confirm: "true",
          import_data: import_data2,
          batch_year_id: batch_year.id
        }
      }.to change(Book, :count).by(1)

      expect(response).to redirect_to(books_path)
      follow_redirect!
      expect(response.body).to include("成功匯入 1 本書籍")
      expect(Book.find_by(title: "UTF8書", batch_year_id: batch_year.id)).to be_present
    end

    it "confirms import using per-row 屆數ID when form 屆數 is blank" do
      csv = <<~CSV
        書名,ISBN,屆數ID,來源,登錄號
        屆數ID匯入,9789861817286,#{batch_year.id},圖書館館藏,12345678
      CSV
      tf = Tempfile.new([ "books_batch_id", ".csv" ])
      tf.write("\uFEFF#{csv}")
      tf.close

      post import_books_path, params: {
        file: Rack::Test::UploadedFile.new(tf.path, "text/csv")
      }
      File.unlink(tf.path)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("本新書")

      m = response.body.match(/name=(?:"|')import_data(?:"|')[^>]*value=(?:"|')(?<data>[^"']+)(?:"|')/)
      import_data = m && m[:data]
      expect(import_data).to be_present

      expect {
        post import_books_path, params: {
          confirm: "true",
          import_data: import_data
        }
      }.to change(Book, :count).by(1)

      expect(response).to redirect_to(books_path)
      expect(Book.find_by(title: "屆數ID匯入", batch_year_id: batch_year.id)).to be_present
    end
  end
end
