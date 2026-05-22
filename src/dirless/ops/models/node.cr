require "granite"


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
      column cpu_count : Int32?
      column memory_gb : Int32?
      column free_memory_mb : Int32?
      column free_disk_gb : Int32?
      column load_5m : Float64?
      column last_probed_at : Time?
      column probe_error : String?
      column services_json : String?
      column syncthing_status_json : String?
      column probe_failure_count : Int32 = 0
      timestamps

      def to_response
        {
          "id"             => id,
          "name"           => name,
          "ip"             => ip,
          "region"         => region,
          "provider"       => provider,
          "is_primary"     => is_primary,
          "cpu_count"      => cpu_count,
          "memory_gb"      => memory_gb,
          "free_memory_mb" => free_memory_mb,
          "free_disk_gb"   => free_disk_gb,
          "load_5m"        => load_5m,
          "last_probed_at" => last_probed_at.try(&.to_rfc3339),
          "probe_error"    => probe_error,
          "created_at"     => created_at.try(&.to_rfc3339),
          "updated_at"     => updated_at.try(&.to_rfc3339),
        }
      end
    end
  end
end
