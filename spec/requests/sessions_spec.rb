require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:batch_year) { create(:batch_year) }

  describe "GET /login" do
    it "shows the login page" do
      get login_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Google")
    end

    it "redirects to root if already logged in" do
      admin = create(:user, :admin, batch_year: batch_year)
      login_as(admin)
      get login_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /google_auth_callback" do
    context "with valid admin auth" do
      let!(:admin) { create(:user, :admin, batch_year: batch_year) }

      it "logs in and redirects to root" do
        mock_google_auth(email: admin.email, name: admin.name)
        get google_auth_callback_path
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include(admin.name)
      end
    end

    context "with superadmin email and no existing user" do
      let!(:batch_year) { create(:batch_year) }

      it "auto-provisions and logs in" do
        email = User::SUPERADMIN_EMAILS.first
        mock_google_auth(email: email, name: "Super Admin")
        get google_auth_callback_path
        expect(response).to redirect_to(root_path)
        expect(User.find_by(email: email)).to be_present
      end
    end

    context "with unknown email" do
      it "redirects to login with alert" do
        mock_google_auth(email: "nobody@example.com")
        get google_auth_callback_path
        expect(response).to redirect_to(login_path)
        follow_redirect!
        expect(response.body).to include("找不到對應的使用者帳號")
      end
    end

    context "with auth failure" do
      it "redirects to login with alert" do
        OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
        get google_auth_callback_path
        # OmniAuth redirects to /auth/failure in test mode
        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "DELETE /logout" do
    it "clears session and redirects to login" do
      admin = create(:user, :admin, batch_year: batch_year)
      login_as(admin)
      delete logout_path
      expect(response).to redirect_to(login_path)
      # Verify session is cleared
      get admin_dashboard_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "sidebar" do
    it "shows logout button and admin nav when logged in" do
      admin = create(:user, :admin, batch_year: batch_year)
      login_as(admin)
      get admin_dashboard_path
      expect(response.body).to include('action="/logout"')
      expect(response.body).to include("登出")
      expect(response.body).to include(admin.name)
      expect(response.body).to include("書籍管理")
      expect(response.body).to include("屆數管理")
      expect(response.body).to include("人員管理")
      expect(response.body).not_to include(loan_history_path)
    end

    it "shows borrow/return nav when logged out" do
      get login_path
      expect(response.body).to include("管理員登入")
      expect(response.body).to include("借還書")
      expect(response.body).not_to include("書籍管理")
      expect(response.body).not_to include("屆數管理")
      expect(response.body).not_to include("人員管理")
      expect(response.body).not_to include("登出")
    end
  end

  describe "require_login" do
    it "redirects unauthenticated users to login" do
      get admin_dashboard_path
      expect(response).to redirect_to(login_path)
    end

    it "allows authenticated users through" do
      admin = create(:user, :admin, batch_year: batch_year)
      login_as(admin)
      get admin_dashboard_path
      expect(response).to have_http_status(:success)
    end
  end
end
