require "grip"
require "./dirless/ops/config"
require "./dirless/ops/db"
require "./dirless/ops/notifier"
require "./dirless/ops/stripe_client"

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
require "./dirless/ops/models/provision_job"
require "./dirless/ops/deployer"
require "./dirless/ops/node_prober"

_notifier = Dirless::Ops::Notifier.new(_config.mail_spool_dir, _config.ops_alert_email, _config.portal_url)

# In --deploy mode, run the deployer and exit (used by systemd timer).
if ARGV.includes?("--deploy")
  runner = Dirless::Ops::Deployer::Runner.new(_config, _notifier)
  runner.run
  exit 0
end

require "./dirless/ops/middleware/api_key"
require "./dirless/ops/poller"
require "./dirless/ops/routes/health"
require "./dirless/ops/routes/customers"
require "./dirless/ops/routes/nodes"
require "./dirless/ops/routes/status"
require "./dirless/ops/routes/portal"
require "./dirless/ops/routes/provision_jobs"
require "./dirless/ops/routes/directory"

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
    @@notifier : Notifier? = nil
    @@stripe_client : StripeClient? = nil

    def self.config : Config
      @@config || raise "Ops.config accessed before initialization"
    end

    def self.config=(config : Config)
      @@config = config
    end

    def self.notifier : Notifier
      @@notifier || raise "Ops.notifier accessed before initialization"
    end

    def self.notifier=(n : Notifier)
      @@notifier = n
    end

    def self.stripe_client : StripeClient?
      @@stripe_client
    end

    def self.stripe_client=(client : StripeClient?)
      @@stripe_client = client
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
            get "/:name/directory/snapshot", Controllers::GetDirectorySnapshot
            post "/:name/directory/snapshot", Controllers::PushDirectorySnapshot
            get "/:name/directory/snapshot/aws-identity-center", Controllers::GetCloudSnapshot
            get "/:name/directory/snapshot/local", Controllers::GetLocalSnapshot
            post "/:name/directory/snapshot/local", Controllers::PushLocalSnapshot
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
            post "/login", Controllers::PortalLogin
            post "/checkout", Controllers::PortalCreateCheckout
            get "/checkout/:session_id", Controllers::PortalVerifyCheckout
            get "/verify-email", Controllers::PortalVerifyEmail
            post "/resend-verification", Controllers::PortalResendVerification
          end

          scope "/provision-jobs" do
            get "/", Controllers::ListProvisionJobs
            get "/:id", Controllers::GetProvisionJob
            patch "/:id", Controllers::UpdateProvisionJob
          end
        end
      end
    end

    Ops.config = _config
    Ops.notifier = _notifier
    if (key = _config.stripe_secret_key) && !key.empty?
      Ops.stripe_client = StripeClient.new(key)
    end

    Poller.new(_config.polling_interval_seconds).start
    NodeProber.new(_config, _notifier).start

    app = Application.new(_config.api_key)
    app.host = _config.host
    app.port = _config.port
    app.run
  end
end
