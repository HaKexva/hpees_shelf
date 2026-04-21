# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Demo mode", type: :request do
  around do |ex|
    old = ENV["DEMO_ENABLED"]
    ENV["DEMO_ENABLED"] = demo_enabled
    ex.run
  ensure
    ENV["DEMO_ENABLED"] = old
  end

  let(:demo_enabled) { "true" }

  def in_demo_shard(&block)
    ActiveRecord::Base.connected_to(shard: :demo, &block)
  end

  it "returns 404 for /demo when DEMO_ENABLED is not true" do
    ENV["DEMO_ENABLED"] = "false"
    get "/demo/books"
    expect(response).to have_http_status(:not_found)
  end

  it "/books is not affected by demo middleware" do
    get "/books"
    expect(response).not_to have_http_status(:not_found)
  end

  it "auto-login creates a demo user in demo shard only" do
    expect do
      post "/demo/demo_login", params: { role: "student" }
    end.to change { session[:demo_user_id] }.from(nil)

    demo_id = session[:demo_user_id]
    expect(User.find_by(id: demo_id)).to be_nil
    expect(in_demo_shard { User.find_by(id: demo_id) }).to be_present
  end

  it "session[:user_id] does not grant access in demo mode" do
    by = BatchYear.create!(batch_number: 99, grade_id: 1, name: "primary")
    primary_user = User.create!(name: "Primary Admin", email: "primary-admin@example.com", admin: true, batch_year: by)

    get "/demo/books", env: { "rack.session" => { user_id: primary_user.id } }
    expect(response).to redirect_to("/demo/demo_login")
  end

  it "URL helpers generate /demo-prefixed paths in demo mode (SCRIPT_NAME)" do
    get "/demo/demo_login"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('action="/demo/demo_login"')
  end

  it "demo:reset truncates and re-seeds demo shard" do
    in_demo_shard do
      BatchYear.create!(batch_number: 50, grade_id: 1, name: "wipe-me")
    end
    expect(in_demo_shard { BatchYear.where(batch_number: 50).count }).to eq(1)

    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["demo:reset"].reenable
    Rake::Task["demo:seed"].reenable
    Rake::Task["demo:reset"].invoke

    expect(in_demo_shard { BatchYear.where(batch_number: 50).count }).to eq(0)
    expect(in_demo_shard { User.where(email: "demo-admin@example.com").count }).to eq(1)
  end
end

