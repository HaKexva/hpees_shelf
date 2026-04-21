# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemoSessionsController, type: :controller do
  render_views

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

  describe "GET #new" do
    it "renders the role picker when not logged in" do
      get :new
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("示範模式登入")
    end

    it "redirects when demo_user_id already in session" do
      session[:demo_user_id] = 123
      get :new
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST #create" do
    it "creates admin user in demo shard and sets session[:demo_user_id]" do
      expect do
        post :create
      end.to change { session[:demo_user_id] }.from(nil)

      demo_id = session[:demo_user_id]
      demo_user = ActiveRecord::Base.connected_to(shard: :demo) { User.find(demo_id) }
      expect(demo_user.admin?).to eq(true)

      primary_user = User.find_by(id: demo_id)
      expect(primary_user).to be_nil
    end
  end

  describe "DELETE #destroy" do
    it "clears demo session key only" do
      demo_user_id = ActiveRecord::Base.connected_to(shard: :demo) do
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
