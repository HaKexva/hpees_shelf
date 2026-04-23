class DemoModeMiddleware
  DEMO_PREFIX = "/demo".freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    path = env["PATH_INFO"].to_s
    return @app.call(env) unless path.start_with?(DEMO_PREFIX)

    return not_found unless ENV["DEMO_ENABLED"].to_s == "true"

    # If someone hits `/demo` or `/demo/login`, do a real redirect so the browser URL
    # becomes `/demo/admin` (instead of rendering dashboard under `/demo/login`).
    if path == "/demo" || path == "/demo/" || path == "/demo/login"
      return [
        302,
        { "Location" => "/demo/admin", "Content-Type" => "text/plain; charset=utf-8" },
        [ "Found" ]
      ]
    end

    env["hpees.demo_mode"] = true
    env["SCRIPT_NAME"] = "#{env['SCRIPT_NAME']}#{DEMO_PREFIX}"
    env["PATH_INFO"] = path.delete_prefix(DEMO_PREFIX)
    # In demo mode, there is no manual login step.
    # Treat `/demo` as the logged-in landing page (dashboard).
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
