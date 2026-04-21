class DemoSessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  def new
    redirect_to root_path if session[:demo_user_id].present?
  end

  def create
    role = params[:role].to_s
    unless %w[admin student].include?(role)
      redirect_to demo_login_path, alert: "請選擇身分。"
      return
    end

    user = find_or_create_demo_user!(role:)
    session[:demo_user_id] = user.id

    redirect_to(role == "admin" ? admin_dashboard_path : root_path, notice: "已以示範模式登入：#{user.name}。")
  end

  def destroy
    session.delete(:demo_user_id)
    redirect_to demo_login_path, notice: "已登出示範模式。"
  end

  private

  def find_or_create_demo_user!(role:)
    ActiveRecord::Base.connected_to(shard: :demo) do
      batch_year = BatchYear.order(:id).first || BatchYear.create!(batch_number: 1, grade_id: 1, name: "第1屆")

      case role
      when "admin"
        User.find_or_create_by!(email: "demo-admin@example.com") do |u|
          u.name = "示範管理員"
          u.admin = true
          u.batch_year = batch_year
        end
      else
        User.find_or_create_by!(email: "demo-student@example.com") do |u|
          u.name = "示範學生"
          u.admin = false
          u.batch_year = batch_year
        end
      end
    end
  end
end
