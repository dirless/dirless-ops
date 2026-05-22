require "granite"


module Dirless
  module Ops
    class HealthCheck < Granite::Base
      connection sqlite
      table health_checks

      column id : Int64, primary: true
      column customer_id : Int64
      column node_id : Int64
      column status : String
      column http_status : Int32?
      column response_time_ms : Int32?
      column tenant_count : Int32?
      column user_count : Int32?
      column error : String?
      column data_updated_at : Time?
      column active_agents : Int32?
      column agents_json : String?
      column checked_at : Time

      def to_response
        {
          "id"               => id,
          "customer_id"      => customer_id,
          "node_id"          => node_id,
          "status"           => status,
          "http_status"      => http_status,
          "response_time_ms" => response_time_ms,
          "tenant_count"     => tenant_count,
          "user_count"       => user_count,
          "error"            => error,
          "checked_at"       => checked_at.try(&.to_rfc3339),
        }
      end
    end
  end
end
