class ApplicationController < ActionController::Base
  # Allow all Safari versions, but still require modern Chrome/Firefox/Opera and block Internet Explorer.
  # from https://edgeapi.rubyonrails.org/classes/ActionController/AllowBrowser/ClassMethods.html
  allow_browser versions: { chrome: 120, firefox: 121, opera: 106, ie: false }

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

  private
    def _csv_escape(value)
      s = value.to_s
      return "\"#{s.gsub('"', '""')}\"" if s.include?(",") || s.include?("\"") || s.include?("\n") || s.include?("\r")
      s
    end
end
