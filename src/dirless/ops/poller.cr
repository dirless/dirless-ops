require "http/client"
require "json"
require "openssl"
require "dirless-http"
require "./models/customer"
require "./models/node"
require "./models/health_check"
require "./models/provision_job"

module Dirless
  module Ops
    class Poller
      RETENTION_HOURS = 24
      # Unverified accounts are throwaway signups (usually bots) - delete them
      # after this window. Never touches provisioned, paid, or checkout-started
      # accounts; see purge_unverified.
      UNVERIFIED_TTL = 2.hours
      # TPDB never reclaims pages freed by DELETE (same trap the agent's
      # local_db avoids with DROP+CREATE), so the health-check churn bloats
      # ops.db without bound - it hit 153 MB in production and dashboard
      # queries took 300-400ms each. VACUUM once per day, and once at boot
      # so a deploy compacts an already-bloated file.
      VACUUM_INTERVAL = 24.hours

      @last_vacuum : Time? = nil

      def initialize(@interval_seconds : Int32)
      end

      def start
        spawn do
          loop do
            begin
              poll
              prune
              purge_unverified
              vacuum_if_due
            rescue ex
              Log.error(exception: ex) { "poller cycle failed" }
            end
            sleep @interval_seconds.seconds
          end
        end
      end

      # Public for specs.
      def vacuum_if_due
        last = @last_vacuum
        return if last && Time.utc - last < VACUUM_INTERVAL
        started = Time.instant
        Granite::Connections["sqlite"].not_nil![:writer].database.exec("VACUUM")
        @last_vacuum = Time.utc
        Log.info { "ops.db VACUUM completed in #{(Time.instant - started).total_seconds.round(1)}s" }
      end

      private def poll
        nodes = Node.all
        customers = Customer.all

        if nodes.empty? || customers.empty?
          Log.debug { "poller: no nodes or customers configured, skipping" }
          return
        end

        nodes.each do |node|
          customers.each do |customer|
            check_health(node, customer)
          end
        end
      end

      private def check_health(node : Node, customer : Customer)
        hostname = "#{customer.name}.#{Ops.config.backend_domain}"
        checked_at = Time.utc
        start_time = Time.instant

        begin
          status_code, body = https_get(node.ip, 443, hostname, "/v1/health")
          elapsed_ms = ((Time.instant - start_time).total_milliseconds).to_i

          tenant_count = nil
          user_count = nil
          data_updated_at = nil
          active_agents = nil
          agents_json = nil
          if status_code == 200
            parsed = JSON.parse(body)
            tenant_count = parsed["tenants"]?.try(&.as_i?)
            user_count = parsed["users"]?.try(&.as_i?)
            data_updated_at = parsed["data_updated_at"]?.try(&.as_s?).try { |str| Time.parse_rfc3339(str) rescue nil }
            active_agents = parsed["active_agents"]?.try(&.as_i?)
            agents_json = parsed["agents"]?.try(&.to_json)

            if (reported_id = parsed["aws_account_id"]?.try(&.as_s?))
              stored_id = customer.aws_account_id
              if stored_id.nil? || stored_id.empty?
                canonical_tid = OpenSSL::HMAC.hexdigest(:sha256, customer.hmac_secret, reported_id)
                customer.aws_account_id = reported_id
                customer.tenant_id = canonical_tid
                customer.cloud_provider = "aws"
                customer.save
                Log.info { "poller: stored aws_account_id=#{reported_id} tenant_id=#{canonical_tid} for customer #{customer.name}" }
              elsif stored_id != reported_id
                Log.error { "poller: aws_account_id conflict for customer #{customer.name}: " \
                            "stored=#{stored_id}, reported=#{reported_id}" }
              end
            end
          end

          hc = HealthCheck.new(
            customer_id: customer.id,
            node_id: node.id,
            status: status_code == 200 ? "up" : "down",
            http_status: status_code,
            response_time_ms: elapsed_ms,
            tenant_count: tenant_count,
            user_count: user_count,
            data_updated_at: data_updated_at,
            active_agents: active_agents,
            agents_json: agents_json,
            error: nil,
            checked_at: checked_at,
          )
          hc.save
        rescue ex
          elapsed_ms = ((Time.instant - start_time).total_milliseconds).to_i

          hc = HealthCheck.new(
            customer_id: customer.id,
            node_id: node.id,
            status: "down",
            http_status: nil,
            response_time_ms: elapsed_ms,
            error: ex.message,
            checked_at: checked_at,
          )
          hc.save
        end
      end

      # Uses TargetedClient to connect to a specific IP while presenting the
      # correct SNI hostname for TLS verification. Unlike the old raw-socket
      # approach, this properly verifies server certificates and handles HTTP
      # response parsing (chunked encoding, content-length, etc.).
      private def https_get(ip : String, port : Int32, hostname : String, path : String) : {Int32, String}
        tls = OpenSSL::SSL::Context::Client.new
        client = Dirless::Net::TargetedClient.new(ip, hostname, port, tls)
        client.connect_timeout = 10.seconds
        client.read_timeout = 10.seconds
        begin
          response = client.get(path)
          {response.status_code, response.body}
        ensure
          client.close rescue nil
        end
      end

      private def prune
        cutoff = Time.utc - RETENTION_HOURS.hours
        HealthCheck.where(:checked_at, :lt, cutoff).delete
      end

      # Delete stale unverified signups. Guards, in order: never touch a
      # provisioned account, a paid/upgraded plan, or an account that has a
      # Stripe customer (checkout was started) - those get human review.
      # Called from the poll loop; public so specs can exercise the guards.
      def purge_unverified
        cutoff = Time.utc - UNVERIFIED_TTL
        Customer.where(email_verified: false, provisioned: false).select.each do |customer|
          created = customer.created_at
          next unless created && created < cutoff
          plan = customer.plan
          next if plan && plan != "free"
          stripe_id = customer.stripe_customer_id
          next if stripe_id && !stripe_id.empty?

          ProvisionJob.where(customer_name: customer.name).delete
          customer.destroy
          Log.info { "purged unverified account #{customer.name} (#{customer.email}, registered #{created})" }
        end
      end
    end
  end
end
