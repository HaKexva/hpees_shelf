# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Books import preview", type: :request do
  let(:batch_year) { create(:batch_year) }

  before { login_as(create(:user, :admin, batch_year: batch_year)) }

  def books_csv_upload(content)
    Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: "books_import.csv")
  end

  describe "POST /books/import" do
    it "parses UTF-8 CSV without corrupting Chinese text" do
      csv = <<~CSV
        書名,ISBN,屆數ID,來源,登錄號
        UTF8書,9789861817286,#{batch_year.id},圖書館館藏,12345678
      CSV
      post import_books_path, params: { file: books_csv_upload(csv) }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("UTF8書")
      expect(response.body).to include("9789861817286")
    end

    it "parses Big5-encoded CSV (common Excel export on Windows)" do
      rows = <<~CSV
        書名,ISBN,屆數ID,來源,登錄號
        Big5書,9789861817286,#{batch_year.id},圖書館館藏,12345678
      CSV
      encoded = rows.encode("Big5")
      post import_books_path, params: {
        file: Rack::Test::UploadedFile.new(StringIO.new(encoded), "text/csv", original_filename: "big5.csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Big5書")
      expect(response.body).to include("9789861817286")
    end

    it "allows editing invalid rows and re-validates on refresh" do
      csv = <<~CSV
        書名,ISBN,屆數ID,來源,登錄號
        壞ISBN書,9789861817280,#{batch_year.id},圖書館館藏,12345678
      CSV
      post import_books_path, params: { file: books_csv_upload(csv) }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("不符合")

      m = response.body.match(/name=(?:"|')import_data(?:"|')[^>]*value=(?:"|')(?<data>[^"']+)(?:"|')/)
      import_data = m && m[:data]
      expect(import_data).to be_present

      post import_books_path, params: {
        refresh_preview: "true",
        import_data: import_data,
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
      csv = <<~CSV
        書名,ISBN,屆數ID,來源
        缺登錄號,9789861817286,#{batch_year.id},圖書館館藏
      CSV
      post import_books_path, params: { file: books_csv_upload(csv) }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("缺登錄號")
      expect(response.body).to include("不符合")
    end

    it "confirms import and creates a library book when preview is valid" do
      csv = <<~CSV
        書名,ISBN,屆數ID,來源,登錄號
        UTF8書,9789861817286,#{batch_year.id},圖書館館藏,12345678
      CSV
      post import_books_path, params: { file: books_csv_upload(csv) }
      expect(response).to have_http_status(:success)
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
