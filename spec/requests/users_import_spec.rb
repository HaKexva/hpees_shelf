# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users import preview", type: :request do
  let(:batch_year) { create(:batch_year) }

  before { login_as(create(:user, :admin, batch_year: batch_year)) }

  describe "POST /users/import" do
    it "allows fixing blank name in the preview table and re-validates on refresh" do
      post import_users_path, params: {
        file: fixture_file_upload("users_import_blank_name.csv", "text/csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("不符合（缺姓名）")

      m = response.body.match(/name=(?:"|')import_data(?:"|')[^>]*value=(?:"|')(?<data>[^"']+)(?:"|')/)
      import_data = m && m[:data]
      expect(import_data).to be_present

      post import_users_path, params: {
        refresh_preview: "true",
        import_data: import_data,
        batch_year_id: batch_year.id,
        edit_rows: {
          "0" => {
            "name" => "補齊姓名"
          }
        }
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("補齊姓名")
      expect(response.body).to include("1 位將匯入")
      expect(response.body).to include("0 位不符合")
    end

    it "marks rows invalid in preview when 學號 is not 6 digits (matches save validation)" do
      post import_users_path, params: {
        file: fixture_file_upload("users_import_bad_student_id.csv", "text/csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("不符合（學號）")
    end

    it "treats em dash and common placeholders in 學號/座號 as blank so the row can import" do
      post import_users_path, params: {
        file: fixture_file_upload("users_import_em_dash_placeholders.csv", "text/csv")
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("0 位不符合")
      expect(response.body).not_to include("不符合（學號）")

      m = response.body.match(/name=(?:"|')import_data(?:"|')[^>]*value=(?:"|')(?<data>[^"']+)(?:"|')/)
      import_data = m && m[:data]
      expect(import_data).to be_present

      post import_users_path, params: {
        refresh_preview: "true",
        import_data: import_data,
        batch_year_id: batch_year.id
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("1 位將匯入")

      m2 = response.body.match(/name=(?:"|')import_data(?:"|')[^>]*value=(?:"|')(?<data>[^"']+)(?:"|')/)
      import_data2 = m2 && m2[:data]
      expect(import_data2).to be_present

      expect {
        post import_users_path, params: {
          confirm: "true",
          import_data: import_data2,
          batch_year_id: batch_year.id
        }
      }.to change(User, :count).by(1)

      u = User.find_by(name: "破折號占位", batch_year_id: batch_year.id)
      expect(u).to be_present
      expect(u.id_number).to be_blank
      expect(u.seat_number).to be_blank
    end

    it "accepts numeric 學號 from JSON preview (Excel-style Float) after refresh" do
      payload = [ { "姓名" => "數字學號", "學號" => 123_456.0, "座號" => 1.0 } ]
      import_data = Base64.strict_encode64(payload.to_json)

      post import_users_path, params: {
        refresh_preview: "true",
        import_data: import_data,
        batch_year_id: batch_year.id
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("1 位將匯入")
      expect(response.body).to include("0 位不符合")
    end
  end
end
