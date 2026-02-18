class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # 預設為 admin（登入系統尚未建立）
  helper_method :current_user, :current_user_admin?

  def current_user
    @current_user ||= User.where(admin: true).order(:id).first
  end

  def current_user_admin?
    current_user&.admin?
  end
end
