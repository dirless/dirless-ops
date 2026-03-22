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
        property created_at : String?
        property updated_at : String?
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
        property error : String?
        property checked_at : String?
      end

      struct CustomerStatusResponse
        include JSON::Serializable

        property id : Int32
        property name : String
        property label : String?
        property aws_account_id : String?
        property nodes : Array(NodeStatusResponse)
      end

      struct PortalAccountResponse
        include JSON::Serializable

        property id : Int32
        property email : String
        property customer_name : String
        property company : String?
        property provisioned : Bool
        property created_at : String?
      end
    end
  end
end
