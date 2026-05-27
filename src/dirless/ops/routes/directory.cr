require "grip"
require "json"
require "openssl/hmac"
require "openssl"
require "dirless-http"
require "../models/customer"
require "../models/node"

module Dirless
  module Ops
    module Controllers
      # Shared helper included by both directory snapshot controllers.
      # Returns the customer's tenant_id, deriving and persisting it if needed.
      # Priority: explicit tenant_id → HMAC(hmac_secret, aws_account_id) → generated random.
      module DirectoryHelper
        private def resolve_tenant_id(customer : Customer) : String?
          if (tid = customer.tenant_id) && !tid.empty?
            return tid
          end
          if (aid = customer.aws_account_id) && !aid.empty? && (secret = customer.hmac_secret)
            return "aws___" + OpenSSL::HMAC.hexdigest(:sha256, secret, aid)
          end
          # Lazy-init: customer predates the tenant_id column. Generate, persist, and return one now.
          new_tid = "aws___" + Random::Secure.hex(32)
          customer.tenant_id = new_tid
          customer.save
          new_tid
        end
      end

      # GET /v1/customers/:name/directory/snapshot
      # Fetches the encrypted snapshot from the customer's backend and returns
      # it as a base64 string inside a JSON envelope: {"blob": "<base64>"}.
      # Returns 204 (no content) if the customer has no snapshot yet.
      class GetDirectorySnapshot
        include Grip::Controllers::HTTP
        include DirectoryHelper

        def get(context : Context) : Context
          name = context.fetch_path_params["name"]
          customer = Customer.find_by(name: name)

          unless customer
            return context.put_status(404).json({"error" => "customer not found"}).halt
          end

          tenant_id = resolve_tenant_id(customer)
          unless tenant_id
            return context.put_status(422).json({
              "error" => "tenant_id cannot be derived: set aws_account_id on customer or set tenant_id explicitly",
            }).halt
          end

          primary_node = Node.all.find(&.is_primary)
          unless primary_node
            return context.put_status(503).json({"error" => "no primary node configured"}).halt
          end

          hostname = "#{customer.name}.dirless.com"
          begin
            status_code, body = https_get(
              primary_node.ip, 443, hostname, "/v1/agent/snapshot",
              customer.hmac_secret, tenant_id
            )

            case status_code
            when 200
              # Backend stores age ciphertext as base64 (same format the syncer writes).
              # Pass through as-is — no extra encoding needed for JSON transport.
              context.put_status(200).json({"blob" => body}).halt
            when 404
              context.put_status(204).halt
            else
              context.put_status(502).json({"error" => "backend returned HTTP #{status_code}"}).halt
            end
          rescue ex
            context.put_status(502).json({"error" => "backend unreachable: #{ex.message}"}).halt
          end
        end

        private def https_get(ip : String, port : Int32, hostname : String, path : String,
                              hmac_secret : String, tenant_id : String) : {Int32, String}
          tls = OpenSSL::SSL::Context::Client.new
          client = Dirless::Net::TargetedClient.new(ip, hostname, port, tls)
          client.connect_timeout = 10.seconds
          client.read_timeout = 30.seconds
          headers = HTTP::Headers{
            "Authorization" => "Bearer #{hmac_secret}",
            "X-Tenant-ID"   => tenant_id,
          }
          begin
            response = client.get(path, headers: headers)
            {response.status_code, response.body}
          ensure
            client.close rescue nil
          end
        end
      end

      # POST /v1/customers/:name/directory/snapshot
      # Accepts {"blob": "<base64>"} (JSON), forwards the base64 string to the
      # customer's backend as an application/octet-stream POST to /v1/syncer/sync.
      class PushDirectorySnapshot
        include Grip::Controllers::HTTP
        include DirectoryHelper

        def post(context : Context) : Context
          name = context.fetch_path_params["name"]
          customer = Customer.find_by(name: name)

          unless customer
            return context.put_status(404).json({"error" => "customer not found"}).halt
          end

          tenant_id = resolve_tenant_id(customer)
          unless tenant_id
            return context.put_status(422).json({
              "error" => "tenant_id cannot be derived: set aws_account_id on customer or set tenant_id explicitly",
            }).halt
          end

          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON: #{ex.message}"}).halt
          end

          blob_b64 = parsed["blob"]?.try(&.as_s)
          unless blob_b64 && !blob_b64.empty?
            return context.put_status(422).json({"error" => "blob field is required"}).halt
          end

          recipient = parsed["recipient"]?.try(&.as_s)
          unless recipient && !recipient.empty?
            return context.put_status(422).json({"error" => "recipient field is required — include the age public key"}).halt
          end

          # blob_b64 is base64-encoded age ciphertext. The backend's syncer/sync endpoint
          # expects base64 (same as what dirless-syncer writes). Pass through as-is.
          primary_node = Node.all.find(&.is_primary)
          unless primary_node
            return context.put_status(503).json({"error" => "no primary node configured"}).halt
          end

          hostname = "#{customer.name}.dirless.com"
          begin
            status_code, response_body = https_post(
              primary_node.ip, 443, hostname, "/v1/syncer/sync",
              customer.hmac_secret, tenant_id, blob_b64,
              recipient: recipient,
            )

            if status_code == 200
              context.put_status(200).json({"status" => "ok"}).halt
            else
              context.put_status(502).json({"error" => "backend returned HTTP #{status_code}: #{response_body}"}).halt
            end
          rescue ex
            context.put_status(502).json({"error" => "backend unreachable: #{ex.message}"}).halt
          end
        end

        private def https_post(ip : String, port : Int32, hostname : String, path : String,
                               hmac_secret : String, tenant_id : String, blob : String,
                               *, recipient : String = "") : {Int32, String}
          tls = OpenSSL::SSL::Context::Client.new
          client = Dirless::Net::TargetedClient.new(ip, hostname, port, tls)
          client.connect_timeout = 10.seconds
          client.read_timeout = 30.seconds
          headers = HTTP::Headers{
            "Authorization"       => "Bearer #{hmac_secret}",
            "X-Tenant-ID"         => tenant_id,
            "Content-Type"        => "application/octet-stream",
            "X-Dirless-Recipient" => recipient,
          }
          begin
            response = client.post(path, headers: headers, body: blob)
            {response.status_code, response.body}
          ensure
            client.close rescue nil
          end
        end
      end
    end
  end
end
