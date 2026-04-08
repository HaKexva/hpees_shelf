OmniAuth.config.test_mode = true

module AuthHelper
  def login_as(user)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: user.google_uid || SecureRandom.hex,
      info: { email: user.email, name: user.name }
    )
    get google_auth_callback_path
  end

  def mock_google_auth(email:, uid: SecureRandom.hex, name: "Test User")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name }
    )
  end
end

RSpec.configure do |config|
  config.include AuthHelper, type: :request

  config.after(:each) do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end
end
