require "json"
require "crypto/subtle"

module Dirless
  module Ops
    class ApiKeyHandler
      include HTTP::Handler

      # Exact path exemptions.
      EXEMPT_PATHS = ["/v1/health"]

      # Prefix exemptions — any path under these is public.
      # Bootstrap and cert endpoints are protected by their own credentials
      # (magic-link tokens and age challenge-response nonces), not the ops API key.
      EXEMPT_PREFIXES = [
        "/v1/portal/bootstrap/",
        "/v1/portal/cert/",
      ]

      def initialize(@api_key : String)
      end

      def call(context : HTTP::Server::Context)
        path = context.request.path
        return call_next(context) if EXEMPT_PATHS.includes?(path)
        return call_next(context) if EXEMPT_PREFIXES.any? { |p| path.starts_with?(p) }

        auth = context.request.headers["Authorization"]?
        token = auth.try { |header| header.starts_with?("Bearer ") ? header[7..] : nil }

        unless token && Crypto::Subtle.constant_time_compare(token, @api_key)
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
