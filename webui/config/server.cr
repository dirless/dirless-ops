INSECURE_DEFAULT_SECRET_KEY_BASE = "dirless-ops-change-me-in-production-32chars!!"

Lucky::Server.configure do |settings|
  settings.host = ENV.fetch("HOST", "127.0.0.1")
  settings.port = ENV.fetch("PORT", "5001").to_i
  settings.secret_key_base = ENV.fetch("SECRET_KEY_BASE", INSECURE_DEFAULT_SECRET_KEY_BASE)
  if settings.secret_key_base == INSECURE_DEFAULT_SECRET_KEY_BASE
    raise "SECRET_KEY_BASE is unset and falling back to the insecure default. Set a real random secret via the SECRET_KEY_BASE env var before starting."
  end
end

Lucky::RouteHelper.configure do |settings|
  settings.base_uri = ENV.fetch("APP_URL", "http://localhost:5001")
end

Lucky::Session.configure do |settings|
  settings.key = ENV.fetch("SESSION_KEY", "dirless-ops-session")
end

Lucky::ErrorHandler.configure do |settings|
  settings.show_debug_output = ENV.fetch("LUCKY_ENV", "production") != "production"
end

Lucky::ForceSSLHandler.configure do |settings|
  settings.enabled = false
end
