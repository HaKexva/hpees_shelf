require "rails_helper"

RSpec.describe User, ".find_by_google_auth" do
  let(:batch_year) { create(:batch_year) }

  let(:auth_hash) do
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-uid-123",
      info: { email: email, name: "Test User" }
    )
  end

  context "with an admin user" do
    let(:email) { "admin@example.com" }
    let!(:admin) { create(:user, :admin, email: email, batch_year: batch_year) }

    it "finds the admin by email" do
      user = User.find_by_google_auth(auth_hash)
      expect(user).to eq(admin)
    end

    it "sets google_uid on first login" do
      User.find_by_google_auth(auth_hash)
      expect(admin.reload.google_uid).to eq("google-uid-123")
    end

    it "finds by google_uid on subsequent logins" do
      admin.update_columns(google_uid: "google-uid-123")
      user = User.find_by_google_auth(auth_hash)
      expect(user).to eq(admin)
    end
  end

  context "with a non-admin user" do
    let(:email) { "student@example.com" }
    let!(:student) { create(:user, email: email, admin: false, batch_year: batch_year) }

    it "returns nil" do
      user = User.find_by_google_auth(auth_hash)
      expect(user).to be_nil
    end
  end

  context "with a superadmin email" do
    let(:email) { User::SUPERADMIN_EMAILS.first }

    context "when user record exists" do
      let!(:existing) { create(:user, email: email, admin: false, batch_year: batch_year) }

      it "finds the user even if not admin" do
        user = User.find_by_google_auth(auth_hash)
        expect(user).to eq(existing)
      end
    end

    context "when no user record exists but batch_years exist" do
      let!(:batch_year) { create(:batch_year) }

      it "auto-provisions a new admin user" do
        user = User.find_by_google_auth(auth_hash)
        expect(user).to be_persisted
        expect(user.email).to eq(email)
        expect(user.admin).to be true
        expect(user.google_uid).to eq("google-uid-123")
      end
    end

    context "when auto-provisioning Ray and 第4屆 exists" do
      let(:email) { "ray120424@gmail.com" }
      let!(:by4) { create(:batch_year, batch_number: 4) }

      before { create(:batch_year, batch_number: 1) }

      it "assigns batch_number 4 as primary batch_year" do
        user = User.find_by_google_auth(auth_hash)
        expect(user).to be_persisted
        expect(user.batch_year).to eq(by4)
      end
    end

    context "when no user record AND no batch_years exist" do
      it "auto-provisions user and creates a batch_year" do
        expect(BatchYear.count).to eq(0)
        user = User.find_by_google_auth(auth_hash)
        expect(user).to be_persisted
        expect(user.admin).to be true
        expect(user.batch_year).to be_present
        expect(BatchYear.count).to eq(1)
      end
    end
  end

  context "with an unknown email" do
    let(:email) { "nobody@example.com" }

    it "returns nil" do
      user = User.find_by_google_auth(auth_hash)
      expect(user).to be_nil
    end
  end
end
