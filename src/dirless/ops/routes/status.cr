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
            node_statuses = nodes.map do |node|
              latest = HealthCheck.first(
                "WHERE customer_id = ? AND node_id = ? ORDER BY checked_at DESC",
                [customer.id, node.id]
              )

              {
                "node_id"          => node.id,
                "node_name"        => node.name,
                "node_ip"          => node.ip,
                "region"           => node.region,
                "is_primary"       => node.is_primary,
                "status"           => latest.try(&.status) || "unknown",
                "http_status"      => latest.try(&.http_status),
                "response_time_ms" => latest.try(&.response_time_ms),
                "tenant_count"     => latest.try(&.tenant_count),
                "user_count"       => latest.try(&.user_count),
                "error"            => latest.try(&.error),
                "checked_at"       => latest.try(&.checked_at.try(&.to_rfc3339)),
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
