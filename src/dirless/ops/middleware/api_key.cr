require "json"

module Dirless
  module Ops
    class ApiKeyHandler
      include HTTP::Handler

      EXEMPT_PATHS = ["/v1/health"]

      def initialize(@api_key : String)
      end

      def call(context : HTTP::Server::Context)
        return call_next(context) if EXEMPT_PATHS.includes?(context.request.path)

        auth = context.request.headers["Authorization"]?
        token = auth.try { |h| h.starts_with?("Bearer ") ? h[7..] : nil }

        unless token == @api_key
          context.response.status_code = 401
          context.response.content_type = "application/json"
          context.response.print({"error" => "unauthorized"}.to_json)
          return
        end

        call_next(context)
      end
    end
  end
end
