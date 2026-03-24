require "grip"
require "../models/customer"
require "../models/node"
require "../models/health_check"

module Dirless
  module Ops
    module Controllers
      class GetStatus
        include Grip::Controllers::HTTP

        def get(context : Context) : Context
          nodes = Node.all
          customers = Customer.all

          result = customers.map do |customer|
            # First pass: collect latest health check per node
            checks = nodes.map do |node|
              {node, HealthCheck.first(
                "WHERE customer_id = ? AND node_id = ? ORDER BY checked_at DESC",
                [customer.id, node.id]
              )}
            end

            # Find the primary node's data_updated_at for lag calculation
            primary_updated_at = checks
              .select { |n, _| n.is_primary }
              .first?.try { |_, hc| hc.try(&.data_updated_at) }

            node_statuses = checks.map do |node, latest|
              node_updated_at = latest.try(&.data_updated_at)

              # Lag = how far behind this node is vs the primary
              lag_seconds = if primary_updated_at && node_updated_at
                              lag = (primary_updated_at - node_updated_at).total_seconds.to_i
                              lag < 0 ? 0 : lag
                            else
                              nil
                            end

              # Parse agents JSON array stored by the poller
              agents = begin
                if (json_str = latest.try(&.agents_json))
                  JSON.parse(json_str).as_a.map do |a|
                    {
                      "agent_id"     => a["agent_id"]?.try(&.as_s),
                      "hostname"     => a["hostname"]?.try(&.as_s),
                      "last_seen_at" => a["last_seen_at"]?.try(&.as_s),
                    }
                  end
                end
              rescue
                nil
              end

              {
                "node_id"                => node.id,
                "node_name"              => node.name,
                "node_ip"                => node.ip,
                "region"                 => node.region,
                "is_primary"             => node.is_primary,
                "status"                 => latest.try(&.status) || "unknown",
                "http_status"            => latest.try(&.http_status),
                "response_time_ms"       => latest.try(&.response_time_ms),
                "tenant_count"           => latest.try(&.tenant_count),
                "user_count"             => latest.try(&.user_count),
                "data_updated_at"        => node_updated_at.try(&.to_rfc3339),
                "replication_lag_seconds" => lag_seconds,
                "active_agents"          => latest.try(&.active_agents),
                "agents"                 => agents,
                "error"                  => latest.try(&.error),
                "checked_at"             => latest.try(&.checked_at.try(&.to_rfc3339)),
              }
            end

            {
              "id"             => customer.id,
              "name"           => customer.name,
              "label"          => customer.label,
              "aws_account_id" => customer.aws_account_id,
              "nodes"          => node_statuses,
            }
          end

          context.put_status(200).json(result).halt
        end
      end
    end
  end
end
