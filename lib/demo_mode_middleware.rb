class DemoModeMiddleware
  DEMO_PREFIX = "/demo".freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    path = env["PATH_INFO"].to_s
    return @app.call(env) unless path.start_with?(DEMO_PREFIX)

    return not_found unless ENV["DEMO_ENABLED"].to_s == "true"

    env["hpees.demo_mode"] = true
    env["SCRIPT_NAME"] = "#{env['SCRIPT_NAME']}#{DEMO_PREFIX}"
    env["PATH_INFO"] = path.delete_prefix(DEMO_PREFIX)
    # `/demo` should behave like a logged-in landing page (dashboard).
    if env["PATH_INFO"].empty? || env["PATH_INFO"] == "/"
      env["PATH_INFO"] = "/admin"
      env["hpees.demo_auto_login"] = true
    end

    ActiveRecord::Base.connected_to(shard: :demo) do
      @app.call(env)
    end
  end

  private

  def not_found
    [ 404, { "Content-Type" => "text/plain; charset=utf-8" }, [ "Not Found" ] ]
  end
end
