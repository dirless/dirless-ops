class AppServer < Lucky::BaseAppServer
  def middleware : Array(HTTP::Handler)
    [
      Lucky::HttpMethodOverrideHandler.new,
      Lucky::LogHandler.new,
      Lucky::ErrorHandler.new(Errors::Show),
      Lucky::RemoteIpHandler.new,
      Lucky::RouteHandler.new,
      Lucky::StaticFileHandler.new("public", fallthrough: false, directory_listing: false),
      Lucky::RouteNotFoundHandler.new,
    ] of HTTP::Handler
  end

  def listen
    server.bind_tcp(host, port)
    Log.info { "Listening on http://#{host}:#{port}" }
    server.listen
  end
end
