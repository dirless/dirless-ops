require "http/client"
require "json"
require "openssl"
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
          status_code, body = https_get_to_ip(node.ip, 443, hostname, "/v1/health")
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

      # Connect to a specific IP but present the given hostname for SNI and the Host header.
      # Crystal's HTTP::Client uses the connection host as SNI, so we do the TLS handshake
      # manually to send the correct SNI while targeting a specific IP.
      private def https_get_to_ip(ip : String, port : Int32, hostname : String, path : String) : {Int32, String}
        tcp = TCPSocket.new(ip, port, connect_timeout: 10.seconds)
        ctx = OpenSSL::SSL::Context::Client.new
        ctx.verify_mode = OpenSSL::SSL::VerifyMode::NONE
        ssl = OpenSSL::SSL::Socket::Client.new(tcp, context: ctx, hostname: hostname, sync_close: true)

        ssl << "GET #{path} HTTP/1.1\r\nHost: #{hostname}\r\nConnection: close\r\n\r\n"
        ssl.flush

        raw = ssl.gets_to_end
        ssl.close

        lines = raw.split("\r\n")
        status_code = lines.first?.try { |l| l.split(" ")[1]?.try(&.to_i?) } || 0
        body = raw.split("\r\n\r\n", 2)[1]? || ""

        {status_code, body}
      end

      private def prune
        cutoff = Time.utc - RETENTION_HOURS.hours
        HealthCheck.where(:checked_at, :lt, cutoff).delete
      end
    end
  end
end
