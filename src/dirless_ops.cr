require "grip"
require "./dirless/ops/config"
require "./dirless/ops/db"

# Load config and register Granite connection BEFORE requiring models.
# Granite's `connection` macro validates the connection exists at class-load
# time, so setup_db must run first.
_config = Dirless::Ops::Config.load(
  ENV.fetch("DIRLESS_OPS_CONFIG", "/etc/dirless-ops/dirless-ops.toml")
)
Dirless::Ops.setup_db(_config.database_path)

require "./dirless/ops/models/customer"
require "./dirless/ops/models/node"
require "./dirless/ops/models/health_check"
require "./dirless/ops/models/customer_account"
require "./dirless/ops/middleware/api_key"
require "./dirless/ops/poller"
require "./dirless/ops/routes/health"
require "./dirless/ops/routes/customers"
require "./dirless/ops/routes/nodes"
require "./dirless/ops/routes/status"
require "./dirless/ops/routes/portal"

module Dirless
  module Ops
    class ContentTypeHandler
      include HTTP::Handler

      def call(context : HTTP::Server::Context)
        if context.request.method == "POST" || context.request.method == "PATCH"
          ct = context.request.headers["Content-Type"]?
          unless ct && ct.starts_with?("application/json")
            context.response.status_code = 415
            context.response.content_type = "application/json"
            context.response.print({"error" => "Content-Type must be application/json"}.to_json)
            return
          end
        end
        call_next(context)
      end
    end

    @@config : Config? = nil

    def self.config : Config
      @@config || raise "Ops.config accessed before initialization"
    end

    def self.config=(config : Config)
      @@config = config
    end

    class Application
      include Grip::Application

      property environment : String = ENV["DIRLESS_OPS_ENV"]? || "PRODUCTION"

      def initialize(api_key : String)
        @handlers = [
          Grip::Handlers::Log.new,
          ContentTypeHandler.new,
          ApiKeyHandler.new(api_key),
          Grip::Handlers::HTTP.new,
        ] of HTTP::Handler

        scope "/v1" do
          get "/health", Controllers::Health

          scope "/customers" do
            get "/", Controllers::ListCustomers
            post "/", Controllers::CreateCustomer
            get "/:name", Controllers::GetCustomer
            patch "/:name", Controllers::UpdateCustomer
            delete "/:name", Controllers::DeleteCustomer
          end

          scope "/nodes" do
            get "/", Controllers::ListNodes
            post "/", Controllers::CreateNode
            get "/:name", Controllers::GetNode
            patch "/:name", Controllers::UpdateNode
            delete "/:name", Controllers::DeleteNode
          end

          get "/status", Controllers::GetStatus

          scope "/portal" do
            post "/register", Controllers::PortalRegister
            post "/login",    Controllers::PortalLogin
          end
        end
      end
    end

    Ops.config = _config

    Poller.new(_config.polling_interval_seconds).start

    app = Application.new(_config.api_key)
    app.host = _config.host
    app.port = _config.port
    app.run
  end
end
