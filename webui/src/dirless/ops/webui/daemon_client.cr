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
          status.find { |c| c.name == name }
        end

        def portal_register(email : String, password : String, first_name : String, last_name : String, company : String, country : String) : PortalAccountResponse
          PortalAccountResponse.from_json(post("/v1/portal/register", {"email" => email, "password" => password, "first_name" => first_name, "last_name" => last_name, "company" => company, "country" => country}))
        end

        def portal_login(email : String, password : String) : PortalAccountResponse
          PortalAccountResponse.from_json(post("/v1/portal/login", {"email" => email, "password" => password}))
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

        def verify_checkout_session(session_id : String) : PortalAccountResponse
          PortalAccountResponse.from_json(get("/v1/portal/checkout/#{session_id}"))
        end

        def verify_email(token : String) : PortalAccountResponse
          PortalAccountResponse.from_json(get("/v1/portal/verify-email?token=#{URI.encode_path(token)}"))
        end

        def resend_verification(customer_name : String) : Nil
          post("/v1/portal/resend-verification", {"customer_name" => customer_name})
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
