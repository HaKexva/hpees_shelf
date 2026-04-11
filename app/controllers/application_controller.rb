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
    # Remember GET query on list pages so redirects after create/update/import/bulk keep filters + sort (HAK-117).
    BOOKS_LIST_QUERY_KEYS = %w[batch_year_id q source status sort inventory_sort].freeze
    USERS_LIST_QUERY_KEYS = %w[q_name q_seat_number q_id_number batch_year_id sort].freeze

    def remember_books_list_query!
      session[:books_list_query] = request.query_parameters.slice(*BOOKS_LIST_QUERY_KEYS).compact_blank
    end

    def remember_users_list_query!
      session[:users_list_query] = request.query_parameters.slice(*USERS_LIST_QUERY_KEYS).compact_blank
    end

    def books_list_query_hash
      (session[:books_list_query].presence || {}).stringify_keys
    end

    def users_list_query_hash
      (session[:users_list_query].presence || {}).stringify_keys
    end

    def books_bulk_redirect_query
      h = books_list_query_hash.dup
      BOOKS_LIST_QUERY_KEYS.each do |key|
        h[key] = params[key] if params[key].present?
      end
      h.compact_blank
    end

    def users_bulk_redirect_query
      h = users_list_query_hash.dup
      USERS_LIST_QUERY_KEYS.each do |key|
        h[key] = params[key] if params[key].present?
      end
      h.compact_blank
    end

    def _csv_escape(value)
      s = value.to_s
      return "\"#{s.gsub('"', '""')}\"" if s.include?(",") || s.include?("\"") || s.include?("\n") || s.include?("\r")
      s
    end
end
