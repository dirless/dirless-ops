require "json"
require "log"
require "./models/node"

module Dirless
  module Ops
    class NodeProber
      Log = ::Log.for("dirless-node-prober")

      SSH_KEY               = "/etc/dirless-ops/ansible/backend-atlantic.pem"
      SSH_PORT              = "39124"
      PROBE                 = "/usr/local/bin/dirless-probe"
      PROBE_ALERT_THRESHOLD = 3

      def initialize(@config : Config, @notifier : Notifier)
      end

      def run
        nodes = Node.all
        if nodes.empty?
          Log.info { "No nodes configured, skipping probe" }
          return
        end
        nodes.each { |node| probe(node) }
      end

      private def probe(node : Node)
        Log.info { "Probing #{node.name} (#{node.ip})" }

        was_healthy = node.probe_error.nil? && !node.last_probed_at.nil?

        stdout = IO::Memory.new
        stderr = IO::Memory.new

        status = Process.run(
          "ssh",
          args: [
            "-i", SSH_KEY,
            "-p", SSH_PORT,
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=no",
            "-o", "BatchMode=yes",
            "root@#{node.ip}",
            PROBE,
          ],
          output: stdout,
          error: stderr
        )

        now = Time.utc

        if status.success?
          begin
            data = JSON.parse(stdout.to_s.strip)
            node.cpu_count = data["cpu_count"]?.try(&.as_i?)
            node.memory_gb = data["total_memory_mb"]?.try(&.as_i?).try { |m| (m / 1024.0).ceil.to_i }
            node.free_memory_mb = data["free_memory_mb"]?.try(&.as_i?)
            node.load_5m = data["load_5m"]?.try(&.as_f?)
            node.free_disk_gb = data["free_disk_gb"]?.try(&.as_i?)
            node.last_probed_at = now
            node.probe_error = nil
            node.probe_failure_count = 0
            node.services_json = fetch_services(node.ip)
            node.syncthing_status_json = {
              "completion" => data["syncthing_completion"]?,
              "needBytes"  => data["syncthing_need_bytes"]?,
            }.to_json if data["syncthing_completion"]?
            node.save
            Log.info { "Probe OK for #{node.name}" }
          rescue ex
            node.last_probed_at = now
            node.probe_error = "parse error: #{ex.message}"
            node.save
            Log.error { "Failed to parse probe output for #{node.name}: #{ex.message}" }
          end
        else
          error = stderr.to_s.strip.presence || "ssh failed (exit #{status.exit_code})"
          node.last_probed_at = now
          node.probe_error = error
          node.probe_failure_count = (node.probe_failure_count || 0) + 1
          node.save
          Log.warn { "Probe failed for #{node.name} (#{node.probe_failure_count} consecutive): #{error}" }
          if node.probe_failure_count == PROBE_ALERT_THRESHOLD
            @notifier.probe_failing(node.name, node.ip, error, node.probe_failure_count)
          end
        end
      end
      # Returns a JSON string mapping customer_name → active state, e.g.
      # {"xyz-5001":"active","abc-5000":"inactive"}
      private def fetch_services(ip : String) : String
        stdout = IO::Memory.new
        status = Process.run(
          "ssh",
          args: [
            "-i", SSH_KEY,
            "-p", SSH_PORT,
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=no",
            "-o", "BatchMode=yes",
            "root@#{ip}",
            "systemctl list-units --all --no-pager 'dirless-backend@*' --output=json 2>/dev/null",
          ],
          output: stdout,
          error: Process::Redirect::Close
        )

        return "{}" unless status.success?

        services = {} of String => String
        JSON.parse(stdout.to_s).as_a.each do |unit|
          unit_name = unit["unit"]?.try(&.as_s) || next
          customer = unit_name.lchop("dirless-backend@").rchop(".service")
          next if customer.empty?
          services[customer] = unit["active"]?.try(&.as_s) || "unknown"
        end
        services.to_json
      rescue
        "{}"
      end

  end
end
end

