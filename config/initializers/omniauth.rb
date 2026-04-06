Rails.application.config.middleware.use OmniAuth::Builder do
  if Rails.env.production?
    provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"]
  else
    provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"], redirect_uri: "http://127.0.0.1:3000/google_auth_callback", callback_path: "/google_auth_callback"
  end
end
OmniAuth.config.allowed_request_methods = %i[get]
