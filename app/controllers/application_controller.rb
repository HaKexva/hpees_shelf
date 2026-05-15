class ApplicationController < ActionController::Base
  # Allow all Safari versions, but still require modern Chrome/Firefox/Opera and block Internet Explorer.
  # from https://edgeapi.rubyonrails.org/classes/ActionController/AllowBrowser/ClassMethods.html
  allow_browser versions: { chrome: 120, firefox: 121, opera: 106, ie: false }

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_login
  helper_method :current_user,
                :current_user_admin?,
                :users_list_query_hash,
                :books_list_query_hash,
                :demo_mode?,
                :current_batch_year_id,
                :global_batch_year_locked?,
                :current_batch_year

  def demo_mode?
    request.env["hpees.demo_mode"] == true
  end

  def current_user
    if demo_mode?
      return @current_demo_user if defined?(@current_demo_user)

      @current_demo_user =
        if session[:demo_user_id]
          ApplicationRecord.connected_to(shard: :demo) do
            User.find_by(id: session[:demo_user_id])
          end
        end
      return @current_demo_user
    end

    if session[:user_id]
      @current_user ||= User.find_by(id: session[:user_id])
      session.delete(:user_id) if @current_user.nil?
    end
    @current_user
  end

  def current_user_admin?
    current_user&.admin?
  end

  def require_login
    # In demo mode, always ensure a demo user exists (no explicit login step).
    if demo_mode? && session[:demo_user_id].blank?
      user = find_or_create_demo_admin_user!
      session[:demo_user_id] = user.id
    end

    unless current_user
      # Demo mode entry point is `/demo` (middleware maps it to `/demo/admin` and auto-logins).
      redirect_to(demo_mode? ? root_path : login_path)
    end
  end

  private
    def current_batch_year_id
      v = session[:current_batch_year_id]
      return "all" if v.blank? || v == "all"
      v.to_i.positive? ? v.to_i : "all"
    end

    def global_batch_year_locked?
      current_batch_year_id != "all"
    end

    def current_batch_year
      id = current_batch_year_id
      return nil if id == "all"

      BatchYear.find_by(id: id)
    end

    def apply_current_batch_year_filter!(key = :batch_year_id)
      return unless global_batch_year_locked?

      # When a global batch year is selected, it becomes the canonical filter;
      # page-level batch_year_id params are ignored/overridden.
      params[key] = current_batch_year_id.to_s
    end

    # Remember GET query on list pages so redirects after create/update/import/bulk keep filters + sort (HAK-117).
    BOOKS_LIST_QUERY_KEYS = %w[batch_year_id q source status sort inventory_sort].freeze
    USERS_LIST_QUERY_KEYS = %w[q_name q_seat_number q_id_number batch_year_id sort].freeze

    def remember_books_list_query!
      h = request.query_parameters.slice(*BOOKS_LIST_QUERY_KEYS).compact_blank
      h = h.merge("source" => "teachers_all") if h["source"].to_s.strip == "owned_by_teacher"
      session[:books_list_query] = h
    end

    def remember_users_list_query!
      session[:users_list_query] = request.query_parameters.slice(*USERS_LIST_QUERY_KEYS).compact_blank
    end

    def books_list_query_hash
      h = (session[:books_list_query].presence || {}).stringify_keys
      h = h.merge("source" => "teachers_all") if h["source"].to_s.strip == "owned_by_teacher"
      h
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

    def find_or_create_demo_admin_user!
      ApplicationRecord.connected_to(shard: :demo) do
        batch_year = BatchYear.order(:id).first || BatchYear.create!(batch_number: 1, grade_id: 1, name: "第1屆")

        User.find_or_create_by!(email: "demo-admin@example.com") do |u|
          u.name = "示範管理員"
          u.admin = true
          u.batch_year = batch_year
        end
      end
    end
end
