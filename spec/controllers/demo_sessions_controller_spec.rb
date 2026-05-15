# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemoSessionsController, type: :controller do
  around do |ex|
    old = ENV["DEMO_ENABLED"]
    ENV["DEMO_ENABLED"] = "true"
    ex.run
  ensure
    ENV["DEMO_ENABLED"] = old
  end

  before do
    request.env["hpees.demo_mode"] = true
  end

  describe "DELETE #destroy" do
    it "clears demo session key only" do
      demo_user_id = ApplicationRecord.connected_to(shard: :demo) do
        by = BatchYear.create!(batch_number: 1, grade_id: 1, name: "demo")
        User.create!(name: "Demo", email: "demo@example.com", admin: false, batch_year: by).id
      end

      session[:demo_user_id] = demo_user_id
      session[:user_id] = 2
      delete :destroy
      expect(session[:demo_user_id]).to be_nil
      expect(session[:user_id]).to eq(2)
    end
  end
end
