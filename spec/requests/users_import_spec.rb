# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users import preview", type: :request do
  let(:batch_year) { create(:batch_year) }

  before { login_as(create(:user, :admin, batch_year: batch_year)) }

  describe "POST /users/import" do
    it "parses .xlsx via Roo without corrupting Chinese text" do
      xlsx_bytes = UsersImportXlsxBuilder.build(batch_year_id: batch_year.id)
      post import_users_path, params: {
        file: Rack::Test::UploadedFile.new(StringIO.new(xlsx_bytes), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", original_filename: "users_import.xlsx")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("XLSX學生")
      expect(response.body).to include("601234")
    end

    it "allows fixing blank name in the preview table and imports on confirm" do
      csv = <<~CSV
        姓名,學號,座號,屆數ID,電子信箱,管理員
        ,123456,1,#{batch_year.id},,否
      CSV
      post import_users_path, params: {
        file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "t.csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("不符合（缺姓名")

      m = response.body.match(/name=(?:"|')import_data(?:"|')[^>]*value=(?:"|')(?<data>[^"']+)(?:"|')/)
      import_data = m && m[:data]
      expect(import_data).to be_present

      expect {
        post import_users_path, params: {
          confirm: "true",
          import_data: import_data,
          edit_rows: {
            "0" => {
              "name" => "補齊姓名"
            }
          }
        }
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(users_path)
      expect(User.find_by(name: "補齊姓名", batch_year_id: batch_year.id)).to be_present
    end

    it "marks rows invalid in preview when 學號 is not 6 digits (matches save validation)" do
      csv = <<~CSV
        姓名,學號,座號,屆數ID,電子信箱,管理員
        王小明,12345,1,#{batch_year.id},,否
      CSV
      post import_users_path, params: {
        file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "t.csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("不符合（學號）")
    end

    it "treats em dash and common placeholders in 學號/座號 as blank so the row can import" do
      csv = <<~CSV
        姓名,學號,座號,屆數ID,電子信箱,管理員
        破折號占位,—,—,#{batch_year.id},,否
      CSV
      post import_users_path, params: {
        file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "t.csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("0 位不符合")
      expect(response.body).not_to include("不符合（學號）")

      m = response.body.match(/name=(?:"|')import_data(?:"|')[^>]*value=(?:"|')(?<data>[^"']+)(?:"|')/)
      import_data = m && m[:data]
      expect(import_data).to be_present

      expect {
        post import_users_path, params: {
          confirm: "true",
          import_data: import_data
        }
      }.to change(User, :count).by(1)

      u = User.find_by(name: "破折號占位", batch_year_id: batch_year.id)
      expect(u).to be_present
      expect(u.id_number).to be_blank
      expect(u.seat_number).to be_blank
    end

    it "accepts numeric 學號 from JSON preview (Excel-style Float) on confirm" do
      payload = [ { "姓名" => "數字學號", "學號" => 123_456.0, "座號" => 1.0, "屆數ID" => batch_year.id, "電子信箱" => "", "管理員" => "否" } ]
      import_data = Base64.strict_encode64(payload.to_json)

      expect {
        post import_users_path, params: {
          confirm: "true",
          import_data: import_data
        }
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(users_path)
      u = User.find_by(name: "數字學號", batch_year_id: batch_year.id)
      expect(u).to be_present
      expect(u.id_number).to eq("123456")
      expect(u.email).to eq("123456@hpees.tp.edu.tw")
    end

    it "imports an admin row with explicit email" do
      csv = <<~CSV
        姓名,學號,座號,屆數ID,電子信箱,管理員
        老師甲,—,—,#{batch_year.id},teacher1@example.com,是
      CSV
      post import_users_path, params: {
        file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "t.csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("1 位將匯入")

      m = response.body.match(/name=(?:"|')import_data(?:"|')[^>]*value=(?:"|')(?<data>[^"']+)(?:"|')/)
      import_data = m && m[:data]
      expect(import_data).to be_present

      expect {
        post import_users_path, params: {
          confirm: "true",
          import_data: import_data
        }
      }.to change(User, :count).by(1)

      u = User.find_by(name: "老師甲", batch_year_id: batch_year.id, admin: true)
      expect(u).to be_present
      expect(u.email).to eq("teacher1@example.com")
      expect(u.id_number).to be_blank
    end

    it "includes 電子信箱 in CSV export headers" do
      get export_users_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("電子信箱")
      expect(response.body).to include("姓名")
    end

    it "imports 電子信箱 from the row when provided" do
      payload = [
        {
          "姓名" => "自訂信箱",
          "學號" => "601234",
          "座號" => "1",
          "電子信箱" => "custom.user@example.com",
          "屆數ID" => batch_year.id,
          "管理員" => "否"
        }
      ]
      import_data = Base64.strict_encode64(payload.to_json)

      expect {
        post import_users_path, params: {
          confirm: "true",
          import_data: import_data
        }
      }.to change(User, :count).by(1)

      u = User.find_by(name: "自訂信箱", batch_year_id: batch_year.id)
      expect(u).to be_present
      expect(u.email).to eq("custom.user@example.com")
    end
  end
end
