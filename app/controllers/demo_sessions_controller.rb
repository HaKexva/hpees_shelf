class DemoSessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  def new
    redirect_to root_path if session[:demo_user_id].present?
  end

  def create
    user = find_or_create_demo_admin_user!
    session[:demo_user_id] = user.id

    redirect_to admin_dashboard_path, notice: "已以示範模式登入：#{user.name}。"
  end

  def destroy
    session.delete(:demo_user_id)
    redirect_to demo_login_path, notice: "已登出示範模式。"
  end

  private

  def find_or_create_demo_admin_user!
    super
  end
end
