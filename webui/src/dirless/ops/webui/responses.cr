require "json"

module Dirless
  module Ops
    module WebUI
      struct CustomerResponse
        include JSON::Serializable

        property id : Int32
        property name : String
        property label : String?
        property hmac_secret : String
        property aws_account_id : String?
        property notes : String?
        property port : Int32
        property created_at : String?
        property updated_at : String?
      end

      struct NodeResponse
        include JSON::Serializable

        property id : Int32
        property name : String
        property ip : String
        property region : String
        property provider : String
        property is_primary : Bool
        property cpu_count : Int32?
        property memory_gb : Int32?
        property free_memory_mb : Int32?
        property free_disk_gb : Int32?
        property load_5m : Float64?
        property last_probed_at : String?
        property probe_error : String?
        property created_at : String?
        property updated_at : String?
      end

      struct AgentInfo
        include JSON::Serializable

        property agent_id : String?
        property hostname : String?
        property last_seen_at : String?
      end

      struct NodeStatusResponse
        include JSON::Serializable

        property node_id : Int32
        property node_name : String
        property node_ip : String
        property region : String
        property is_primary : Bool
        property status : String
        property http_status : Int32?
        property response_time_ms : Int32?
        property tenant_count : Int32?
        property user_count : Int32?
        property data_updated_at : String?
        property replication_lag_seconds : Int32?
        property active_agents : Int32?
        property agents : Array(AgentInfo)?
        property error : String?
        property checked_at : String?
        property service_state : String?
        property syncthing_completion : Int32?
        property syncthing_need_bytes : Int64?
      end

      struct CustomerStatusResponse
        include JSON::Serializable

        property id : Int32
        property name : String
        property label : String?
        property aws_account_id : String?
        property nodes : Array(NodeStatusResponse)
      end

      struct ProvisionJobResponse
        include JSON::Serializable

        property id : Int32
        property customer_name : String
        property status : String
        property error : String?
        property created_at : String?
        property started_at : String?
        property completed_at : String?
      end

      struct PortalAccountResponse
        include JSON::Serializable

        property id : Int32
        property email : String
        property customer_name : String
        property first_name : String?
        property last_name : String?
        property company : String?
        property country : String?
        property provisioned : Bool
        property plan : String
        property created_at : String?
      end

      struct CheckoutSessionResponse
        include JSON::Serializable

        property url : String
      end
    end
  end
end
