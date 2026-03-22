require "granite"
require "granite/adapter/sqlite"

module Dirless
  module Ops
    class Node < Granite::Base
      connection sqlite
      table nodes

      column id : Int64, primary: true
      column name : String
      column ip : String
      column region : String
      column provider : String
      column is_primary : Bool
      timestamps

      def to_response
        {
          "id"         => id,
          "name"       => name,
          "ip"         => ip,
          "region"     => region,
          "provider"   => provider,
          "is_primary" => is_primary,
          "created_at" => created_at.try(&.to_rfc3339),
          "updated_at" => updated_at.try(&.to_rfc3339),
        }
      end
    end
  end
end
