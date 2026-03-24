require "http/client"
require "json"
require "openssl"
require "dirless-http"
require "./models/customer"
require "./models/node"
require "./models/health_check"

module Dirless
  module Ops
    class Poller
      RETENTION_HOURS = 24

      def initialize(@interval_seconds : Int32)
      end

      def start
        spawn do
          loop do
            begin
              poll
              prune
            rescue ex
              Log.error(exception: ex) { "poller cycle failed" }
            end
            sleep @interval_seconds.seconds
          end
        end
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
        hostname = "#{customer.name}.dirless.com"
        checked_at = Time.utc
        start_time = Time.instant

        begin
          status_code, body = https_get(node.ip, 443, hostname, "/v1/health")
          elapsed_ms = ((Time.instant - start_time).total_milliseconds).to_i

          tenant_count = nil
          user_count = nil
          if status_code == 200
            parsed = JSON.parse(body)
            tenant_count = parsed["tenants"]?.try(&.as_i?)
            user_count = parsed["users"]?.try(&.as_i?)
          end

          hc = HealthCheck.new(
            customer_id: customer.id,
            node_id: node.id,
            status: status_code == 200 ? "up" : "down",
            http_status: status_code,
            response_time_ms: elapsed_ms,
            tenant_count: tenant_count,
            user_count: user_count,
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
    end
  end
end
