require_relative "boot"

require "rails/all"
require_relative "../lib/demo_mode_middleware"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module HpeesShelf
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # In production, demo routes must use a real second Postgres database. Without this,
    # database.yml would fall back to DATABASE_URL and /demo would read/write production data.
    config.before_configuration do
      next unless ENV["DEMO_ENABLED"].to_s == "true"
      next unless ENV["RAILS_ENV"] == "production"

      demo_url = ENV["DEMO_DATABASE_URL"].to_s.strip
      primary_url = ENV["DATABASE_URL"].to_s.strip

      if demo_url.blank?
        abort <<~MSG
          [demo] DEMO_ENABLED=true in production requires DEMO_DATABASE_URL.
          Create a separate PostgreSQL database for demo, then set DEMO_DATABASE_URL to its URL
          (different from DATABASE_URL). Run migrations on that DB: db:migrate:primary_shard_demo.
        MSG
      end

      if primary_url.present? && demo_url == primary_url
        abort <<~MSG
          [demo] DEMO_DATABASE_URL must not equal DATABASE_URL when DEMO_ENABLED=true.
          Point DEMO_DATABASE_URL at the demo-only database (e.g. second Railway Postgres service).
        MSG
      end
    end

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.middleware.insert_before ActionDispatch::Session::CookieStore, DemoModeMiddleware

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Asia/Taipei" # UTC+8
    # config.eager_load_paths << Rails.root.join("extras")
    config.i18n.default_locale = :"zh-TW"
  end
end
