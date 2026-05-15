# frozen_string_literal: true

# Demo routes (`/demo/*`) use ActiveRecord shard `:demo` (see ApplicationRecord, DemoModeMiddleware).
# In production, `primary_shard_demo` resolves from DEMO_DATABASE_URL; if that is blank,
# database.yml falls back to DATABASE_URL — so demo and real data share one DB.
Rails.application.config.after_initialize do
  next unless ENV["DEMO_ENABLED"].to_s == "true"

  demo_url = ENV["DEMO_DATABASE_URL"].to_s.strip
  primary_url = ENV["DATABASE_URL"].to_s.strip

  if Rails.env.production?
    if demo_url.blank?
      Rails.logger.warn(<<~MSG.squish)
        [demo] DEMO_ENABLED is true but DEMO_DATABASE_URL is unset.
        Demo mode is using DATABASE_URL — demo and production data are NOT isolated.
        Set DEMO_DATABASE_URL to your separate Postgres database URL (and run migrations there).
      MSG
    elsif primary_url.present? && demo_url == primary_url
      Rails.logger.warn(<<~MSG.squish)
        [demo] DEMO_DATABASE_URL is identical to DATABASE_URL.
        Demo and production are not isolated; use a different database URL for the demo shard.
      MSG
    end
  end
end
