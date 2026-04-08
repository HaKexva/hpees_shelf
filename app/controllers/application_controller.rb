class ApplicationController < ActionController::Base
  # Allow all Safari versions, but still require modern Chrome/Firefox/Opera and block Internet Explorer.
  # from https://edgeapi.rubyonrails.org/classes/ActionController/AllowBrowser/ClassMethods.html
  allow_browser versions: { chrome: 120, firefox: 121, opera: 106, ie: false }

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_login
  helper_method :current_user, :current_user_admin?

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def current_user_admin?
    current_user&.admin?
  end

  def require_login
    unless current_user
      redirect_to login_path
    end
  end

  private
    def _csv_escape(value)
      s = value.to_s
      return "\"#{s.gsub('"', '""')}\"" if s.include?(",") || s.include?("\"") || s.include?("\n") || s.include?("\r")
      s
    end
end
