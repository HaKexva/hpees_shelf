Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"],
    callback_path: "/google_auth_callback",
    provider_ignores_state: !Rails.env.production?
end
OmniAuth.config.allowed_request_methods = %i[get]
