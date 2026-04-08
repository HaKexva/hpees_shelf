require "rails_helper"

RSpec.describe User, type: :model do
  describe ".find_by_google_auth" do
    let(:batch_year) { create(:batch_year) }

    it "matches superadmin email case-insensitively and bypasses admin check" do
      user = create(:user, batch_year: batch_year, admin: false, email: "Ray120424@GMAIL.COM")

      auth = {
        "uid" => "google-uid-123",
        "info" => { "email" => "ray120424@gmail.com" }
      }

      expect(described_class.find_by_google_auth(auth)&.id).to eq(user.id)
      expect(user.reload.google_uid).to eq("google-uid-123")
    end

    it "does not allow non-admin when not superadmin" do
      create(:user, batch_year: batch_year, admin: false, email: "someone@example.com")

      auth = {
        "uid" => "google-uid-999",
        "info" => { "email" => "someone@example.com" }
      }

      expect(described_class.find_by_google_auth(auth)).to be_nil
    end
  end
end
