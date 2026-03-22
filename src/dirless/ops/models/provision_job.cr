module Dirless
  module Ops
    class ProvisionJob < Granite::Base
      connection sqlite
      table provision_jobs

      column id : Int64, primary: true
      column customer_name : String
      column status : String = "pending"
      column error : String?
      column created_at : Time?
      column started_at : Time?
      column completed_at : Time?

      def to_response
        {
          "id"            => id,
          "customer_name" => customer_name,
          "status"        => status,
          "error"         => error,
          "created_at"    => created_at.try(&.to_rfc3339),
          "started_at"    => started_at.try(&.to_rfc3339),
          "completed_at"  => completed_at.try(&.to_rfc3339),
        }
      end
    end
  end
end
