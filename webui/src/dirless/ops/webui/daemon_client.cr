require "http/client"
require "json"
require "./responses"

module Dirless
  module Ops
    module WebUI
      class DaemonClient
        class Error < Exception
          getter status : Int32
          getter fields : Hash(String, String)

          def initialize(@status : Int32, message : String, @fields = {} of String => String)
            super(message)
          end
        end

        @url : String
        @api_key : String

        def initialize
          @url = ENV.fetch("DIRLESS_OPS_URL", "http://localhost:5000")
          @api_key = ENV.fetch("DIRLESS_OPS_KEY", "")
        end

        def customers : Array(CustomerResponse)
          Array(CustomerResponse).from_json(get("/v1/customers/"))
        end

        def customer(name : String) : CustomerResponse
          CustomerResponse.from_json(get("/v1/customers/#{name}"))
        end

        def create_customer(params : Hash(String, String)) : CustomerResponse
          CustomerResponse.from_json(post("/v1/customers/", params))
        end

        def delete_customer(name : String) : Nil
          delete("/v1/customers/#{name}")
        end

        def nodes : Array(NodeResponse)
          Array(NodeResponse).from_json(get("/v1/nodes/"))
        end

        def node(name : String) : NodeResponse
          NodeResponse.from_json(get("/v1/nodes/#{name}"))
        end

        def create_node(params : Hash(String, String)) : NodeResponse
          NodeResponse.from_json(post("/v1/nodes/", params))
        end

        def delete_node(name : String) : Nil
          delete("/v1/nodes/#{name}")
        end

        def provision_jobs(status : String? = nil) : Array(ProvisionJobResponse)
          path = "/v1/provision-jobs"
          path += "?status=#{status}" if status
          Array(ProvisionJobResponse).from_json(get(path))
        end

        def status : Array(CustomerStatusResponse)
          Array(CustomerStatusResponse).from_json(get("/v1/status"))
        end

        def customer_status(name : String) : CustomerStatusResponse?
          status.find { |customer| customer.name == name }
        end

        def portal_register(email : String, password : String, first_name : String, last_name : String, company : String, country : String) : CustomerResponse
          CustomerResponse.from_json(post("/v1/portal/register", {"email" => email, "password" => password, "first_name" => first_name, "last_name" => last_name, "company" => company, "country" => country}))
        end

        def portal_login(email : String, password : String) : CustomerResponse
          CustomerResponse.from_json(post("/v1/portal/login", {"email" => email, "password" => password}))
        end

        def create_checkout_session(customer_name : String, plan : String, success_url : String, cancel_url : String) : String
          resp = CheckoutSessionResponse.from_json(post("/v1/portal/checkout", {
            "customer_name" => customer_name,
            "plan"          => plan,
            "success_url"   => success_url,
            "cancel_url"    => cancel_url,
          }))
          resp.url
        end

        def verify_checkout_session(session_id : String) : CustomerResponse
          CustomerResponse.from_json(get("/v1/portal/checkout/#{session_id}"))
        end

        def verify_email(token : String) : CustomerResponse
          CustomerResponse.from_json(get("/v1/portal/verify-email?token=#{URI.encode_path(token)}"))
        end

        def resend_verification(customer_name : String) : Nil
          post("/v1/portal/resend-verification", {"customer_name" => customer_name})
        end

        # Confirms an SSH bootstrap magic-link token.
        # Returns {customer_name, username} on success; raises DaemonClient::Error on failure.
        def confirm_bootstrap(token : String) : {String, String}
          response = HTTP::Client.get(
            "#{@url}/v1/portal/bootstrap/confirm?token=#{URI.encode_path(token)}",
            headers: auth_headers,
          )
          check!(response)
          parsed = JSON.parse(response.body)
          {
            parsed["customer_name"].as_s,
            parsed["username"].as_s,
          }
        end

        # Registers an age public key for this customer (used when the customer
        # generates a keypair in-browser, before the syncer has run).
        def register_age_public_key(customer_name : String, public_key : String) : Nil
          response = HTTP::Client.put(
            "#{@url}/v1/customers/#{customer_name}/directory/public-key",
            headers: json_headers,
            body: {"age_public_key" => public_key}.to_json,
          )
          check!(response)
        end

        # Returns the age public key registered by the syncer for this customer,
        # or nil if the syncer has never run.
        def fetch_age_public_key(customer_name : String) : String?
          response = HTTP::Client.get(
            "#{@url}/v1/customers/#{customer_name}/directory/public-key",
            headers: auth_headers,
          )
          return nil unless response.success?
          JSON.parse(response.body)["age_public_key"]?.try(&.as_s?)
        end

        # Returns the base64-encoded cloud-sourced (aws-identity-center) snapshot blob,
        # or nil if no cloud snapshot exists yet (HTTP 204).
        def fetch_cloud_snapshot(customer_name : String) : String?
          fetch_blob("/v1/customers/#{customer_name}/directory/snapshot/aws-identity-center")
        end

        # Returns the base64-encoded portal-managed local users snapshot blob,
        # or nil if no local snapshot has been written yet (HTTP 204).
        def fetch_local_snapshot(customer_name : String) : String?
          fetch_blob("/v1/customers/#{customer_name}/directory/snapshot/local")
        end

        # Deletes the portal-managed local users snapshot (used during key recovery).
        def delete_local_snapshot(customer_name : String) : Nil
          response = HTTP::Client.delete(
            "#{@url}/v1/customers/#{customer_name}/directory/snapshot/local",
            headers: auth_headers,
          )
          check!(response)
        end

        # Pushes a base64-encoded encrypted local users blob to the customer's backend.
        # The *recipient* is the age public key used to encrypt the blob.
        def push_local_snapshot(customer_name : String, blob_b64 : String, recipient : String = "") : Nil
          payload = {"blob" => blob_b64}
          payload["recipient"] = recipient unless recipient.empty?
          post("/v1/customers/#{customer_name}/directory/snapshot/local", payload)
        end

        # Returns the host authorization config for a customer, or a safe default
        # (enforcement off, no rules) if the backend cannot be reached.
        def fetch_authz_config(customer_name : String) : AuthzConfigResponse
          response = HTTP::Client.get(
            "#{@url}/v1/customers/#{customer_name}/directory/authz-config",
            headers: auth_headers,
          )
          return authz_config_default unless response.success?
          AuthzConfigResponse.from_json(response.body)
        rescue
          authz_config_default
        end

        # Saves the host authorization config for a customer.
        def update_authz_config(customer_name : String, enforce : Bool,
                                rules : Array(HostGroupRuleResponse)) : Nil
          payload = {
            "enforce_group_memberships" => enforce,
            "host_group_rules"          => rules.map { |r| {"group" => r.group, "host" => r.host} },
          }
          response = HTTP::Client.put(
            "#{@url}/v1/customers/#{customer_name}/directory/authz-config",
            headers: json_headers,
            body: payload.to_json,
          )
          check!(response)
        end

        # Updates the cert TTL for a customer. Unit: seconds.
        # min: 3600 (1 hour), max: 2_592_000 (30 days).
        def update_cert_ttl(customer_name : String, cert_ttl_seconds : Int64) : Nil
          response = HTTP::Client.patch(
            "#{@url}/v1/portal/settings",
            headers: json_headers,
            body: {"customer_name" => customer_name, "cert_ttl_seconds" => cert_ttl_seconds}.to_json,
          )
          check!(response)
        end

        private def authz_config_default : AuthzConfigResponse
          AuthzConfigResponse.from_json(%({"enforce_group_memberships":false,"host_group_rules":[]}))
        end

        private def fetch_blob(path : String) : String?
          response = HTTP::Client.get("#{@url}#{path}", headers: auth_headers)
          return nil if response.status_code == 204
          check!(response)
          parsed = JSON.parse(response.body)
          parsed["blob"]?.try(&.as_s)
        end

        private def get(path : String) : String
          response = HTTP::Client.get("#{@url}#{path}", headers: auth_headers)
          check!(response)
          response.body
        end

        private def post(path : String, body : Hash) : String
          response = HTTP::Client.post(
            "#{@url}#{path}",
            headers: json_headers,
            body: body.to_json
          )
          check!(response)
          response.body
        end

        private def delete(path : String) : Nil
          response = HTTP::Client.delete("#{@url}#{path}", headers: auth_headers)
          check!(response)
        end

        private def auth_headers : HTTP::Headers
          HTTP::Headers{"Authorization" => "Bearer #{@api_key}"}
        end

        private def json_headers : HTTP::Headers
          HTTP::Headers{
            "Authorization" => "Bearer #{@api_key}",
            "Content-Type"  => "application/json",
          }
        end

        private def check!(response : HTTP::Client::Response) : Nil
          return if response.success?
          message, fields = begin
            parsed = JSON.parse(response.body)
            msg = parsed["error"]?.try(&.as_s) || response.body
            flds = parsed["fields"]?.try(&.as_h?.try(&.transform_values(&.as_s))) || {} of String => String
            {msg, flds}
          rescue
            {response.body, {} of String => String}
          end
          raise Error.new(response.status_code, message, fields)
        end
      end
    end
  end
end
