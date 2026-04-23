class DemoSessionsController < ApplicationController
  def destroy
    session.delete(:demo_user_id)
    redirect_to root_path, notice: "已登出示範模式。"
  end
end
