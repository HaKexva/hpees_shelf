# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemoModeMiddleware do
  let(:inner_app) do
    lambda do |env|
      [
        200,
        { "Content-Type" => "text/plain" },
        [ "#{env['PATH_INFO']}|#{env['SCRIPT_NAME']}|#{env['hpees.demo_mode']}" ]
      ]
    end
  end

  subject(:middleware) { described_class.new(inner_app) }

  around do |ex|
    old = ENV["DEMO_ENABLED"]
    ENV["DEMO_ENABLED"] = demo_enabled
    ex.run
  ensure
    ENV["DEMO_ENABLED"] = old
  end

  let(:demo_enabled) { "true" }

  it "passes through when path is not /demo-prefixed" do
    status, _headers, body = middleware.call({ "PATH_INFO" => "/books", "SCRIPT_NAME" => "" })
    expect(status).to eq(200)
    expect(body.join).to eq("/books||")
  end

  it "returns 404 for /demo when DEMO_ENABLED is not true" do
    ENV["DEMO_ENABLED"] = "false"
    status, _headers, _body = middleware.call({ "PATH_INFO" => "/demo/books", "SCRIPT_NAME" => "" })
    expect(status).to eq(404)
  end

  it "strips /demo from PATH_INFO and sets SCRIPT_NAME" do
    status, _headers, body = middleware.call({ "PATH_INFO" => "/demo/books", "SCRIPT_NAME" => "" })
    expect(status).to eq(200)
    expect(body.join).to eq("/books|/demo|true")
  end

  it "maps bare /demo to / for routing" do
    status, _headers, body = middleware.call({ "PATH_INFO" => "/demo", "SCRIPT_NAME" => "" })
    expect(status).to eq(200)
    expect(body.join).to eq("/|/demo|true")
  end
end

