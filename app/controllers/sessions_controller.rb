class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  def new
    redirect_to root_path if current_user
  end

  # GET /google_auth_callback — OmniAuth sets request.env["omniauth.auth"]
  def create
    auth = request.env["omniauth.auth"]
    if auth.nil?
      redirect_to login_path, alert: "登入失敗，請重試。"
      return
    end

    user = User.find_by_google_auth(auth)
    if user.nil?
      redirect_to login_path, alert: "找不到對應的使用者帳號，請聯絡管理員。"
      return
    end

    session[:user_id] = user.id
    redirect_to root_path, notice: "已登入：#{user.name}。"
  end

  # DELETE /logout
  def destroy
    reset_session
    redirect_to login_path, notice: "已登出。"
  end
end
