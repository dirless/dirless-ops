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
          # When aws_account_id is known the canonical tenant_id is always
          # HMAC(hmac_secret, aws_account_id). Update the stored value if it
          # doesn't match - this heals stale lazy-generated IDs from before
          # aws_account_id was populated.
          if (aid = customer.aws_account_id) && !aid.empty? && (secret = customer.hmac_secret)
            canonical = OpenSSL::HMAC.hexdigest(:sha256, secret, aid)
            if customer.tenant_id != canonical
              customer.tenant_id = canonical
              customer.save
            end
            return canonical
          end
          if (tid = customer.tenant_id) && !tid.empty?
            return tid
          end
          # Lazy-init: no aws_account_id yet. Generate, persist, and return one now.
          new_tid = Random::Secure.hex(32)
          customer.tenant_id = new_tid
          customer.save
          new_tid
        end
      end

      # Shared HTTP helpers for proxying blob requests to the customer's backend.
      module DirectoryHTTP
        private def backend_json_put(ip : String, hostname : String, path : String,
                                     hmac_secret : String, tenant_id : String,
                                     body : String) : {Int32, String}
          tls = OpenSSL::SSL::Context::Client.new
          client = Dirless::Net::TargetedClient.new(ip, hostname, 443, tls)
          client.connect_timeout = 10.seconds
          client.read_timeout = 30.seconds
          headers = HTTP::Headers{
            "Authorization" => "Bearer #{hmac_secret}",
            "X-Tenant-ID"   => tenant_id,
            "Content-Type"  => "application/json",
          }
          begin
            response = client.put(path, headers: headers, body: body)
            {response.status_code, response.body}
          ensure
            client.close rescue nil
          end
        end

        private def backend_get(ip : String, hostname : String,
                                path : String, hmac_secret : String,
                                tenant_id : String) : {Int32, String}
          tls = OpenSSL::SSL::Context::Client.new
          client = Dirless::Net::TargetedClient.new(ip, hostname, 443, tls)
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

        private def backend_put(ip : String, hostname : String, path : String,
                                hmac_secret : String, tenant_id : String,
                                blob : String, *, recipient : String = "") : {Int32, String}
          tls = OpenSSL::SSL::Context::Client.new
          client = Dirless::Net::TargetedClient.new(ip, hostname, 443, tls)
          client.connect_timeout = 10.seconds
          client.read_timeout = 30.seconds
          headers = HTTP::Headers{
            "Authorization"       => "Bearer #{hmac_secret}",
            "X-Tenant-ID"         => tenant_id,
            "Content-Type"        => "application/octet-stream",
            "X-Dirless-Recipient" => recipient,
          }
          begin
            response = client.put(path, headers: headers, body: blob)
            {response.status_code, response.body}
          ensure
            client.close rescue nil
          end
        end

        # Common setup for directory snapshot controllers.
        # Returns {customer, tenant_id, primary_node} or renders an error and returns nil.
        private def resolve_context(context : HTTP::Server::Context, name : String) : {Customer, String, Node}?
          customer = Customer.find_by(name: name)
          unless customer
            context.put_status(404).json({"error" => "customer not found"}).halt
            return nil
          end

          tenant_id = resolve_tenant_id(customer)
          unless tenant_id
            context.put_status(422).json({
              "error" => "tenant_id cannot be derived: set aws_account_id or tenant_id on the customer",
            }).halt
            return nil
          end

          primary_node = Node.all.find(&.is_primary)
          unless primary_node
            context.put_status(503).json({"error" => "no primary node configured"}).halt
            return nil
          end

          {customer, tenant_id, primary_node}
        end

        private def proxy_blob_get(context : HTTP::Server::Context, path : String) : HTTP::Server::Context
          name = context.fetch_path_params["name"]
          result = resolve_context(context, name)
          return context unless result

          customer, tenant_id, primary_node = result
          hostname = "#{customer.name}.#{Ops.config.backend_domain}"

          begin
            status_code, body = backend_get(primary_node.ip, hostname, path,
              customer.hmac_secret, tenant_id)
            case status_code
            when 200
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

        private def proxy_blob_put(context : HTTP::Server::Context, path : String) : HTTP::Server::Context
          name = context.fetch_path_params["name"]
          result = resolve_context(context, name)
          return context unless result

          customer, tenant_id, primary_node = result

          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON: #{ex.message}"}).halt
          end

          blob_b64 = parsed["blob"]?.try(&.as_s)
          if blob_b64.nil? || blob_b64.empty?
            return context.put_status(422).json({"error" => "blob field is required"}).halt
          end

          recipient = parsed["recipient"]?.try(&.as_s) || ""

          hostname = "#{customer.name}.#{Ops.config.backend_domain}"
          begin
            status_code, response_body = backend_put(
              primary_node.ip, hostname, path,
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
      end

      # GET /v1/customers/:name/directory/public-key
      # Returns the registered age public key for this tenant, or null if not yet set.
      class GetAgePublicKey
        include Grip::Controllers::HTTP
        include DirectoryHelper
        include DirectoryHTTP

        def get(context : Context) : Context
          name = context.fetch_path_params["name"]
          result = resolve_context(context, name)
          return context unless result

          customer, tenant_id, primary_node = result
          hostname = "#{customer.name}.#{Ops.config.backend_domain}"

          begin
            status_code, body = backend_get(primary_node.ip, hostname,
              "/v1/snapshot/public-key", customer.hmac_secret, tenant_id)
            case status_code
            when 200
              context.put_status(200).json(JSON.parse(body)).halt
            else
              context.put_status(502).json({"error" => "backend returned HTTP #{status_code}"}).halt
            end
          rescue ex
            context.put_status(502).json({"error" => "backend unreachable: #{ex.message}"}).halt
          end
        end
      end

      # PUT /v1/customers/:name/directory/public-key
      # Registers or updates the age public key for this tenant.
      # Used by the portal when a customer generates a keypair in-browser.
      class PutAgePublicKey
        include Grip::Controllers::HTTP
        include DirectoryHelper
        include DirectoryHTTP

        def put(context : Context) : Context
          name = context.fetch_path_params["name"]
          result = resolve_context(context, name)
          return context unless result

          customer, tenant_id, primary_node = result
          hostname = "#{customer.name}.#{Ops.config.backend_domain}"

          body = context.request.body.try(&.gets_to_end) || ""

          begin
            tls = OpenSSL::SSL::Context::Client.new
            client = Dirless::Net::TargetedClient.new(primary_node.ip, hostname, 443, tls)
            client.connect_timeout = 10.seconds
            client.read_timeout = 30.seconds
            headers = HTTP::Headers{
              "Authorization" => "Bearer #{customer.hmac_secret}",
              "X-Tenant-ID"   => tenant_id,
              "Content-Type"  => "application/json",
            }
            response = client.put("/v1/snapshot/public-key", headers: headers, body: body)
            client.close rescue nil
            case response.status_code
            when 200
              context.put_status(200).json({"status" => "ok"}).halt
            else
              context.put_status(502).json({"error" => "backend returned HTTP #{response.status_code}: #{response.body}"}).halt
            end
          rescue ex
            context.put_status(502).json({"error" => "backend unreachable: #{ex.message}"}).halt
          end
        end
      end

      # GET /v1/customers/:name/directory/snapshot/aws-identity-center
      # Fetches the cloud-sourced (read-only) encrypted snapshot blob.
      # Returns {"blob": "<base64>"} or 204 if no snapshot yet.
      class GetCloudSnapshot
        include Grip::Controllers::HTTP
        include DirectoryHelper
        include DirectoryHTTP

        def get(context : Context) : Context
          proxy_blob_get(context, "/v1/snapshot/aws-identity-center")
        end
      end

      # DELETE /v1/customers/:name/directory/snapshot/local
      # Wipes the portal-managed local users snapshot (e.g. during key recovery).
      class DeleteLocalSnapshot
        include Grip::Controllers::HTTP
        include DirectoryHelper
        include DirectoryHTTP

        def delete(context : Context) : Context
          name = context.fetch_path_params["name"]
          result = resolve_context(context, name)
          return context unless result

          customer, tenant_id, primary_node = result
          hostname = "#{customer.name}.#{Ops.config.backend_domain}"

          begin
            tls = OpenSSL::SSL::Context::Client.new
            client = Dirless::Net::TargetedClient.new(primary_node.ip, hostname, 443, tls)
            client.connect_timeout = 10.seconds
            client.read_timeout = 30.seconds
            headers = HTTP::Headers{
              "Authorization" => "Bearer #{customer.hmac_secret}",
              "X-Tenant-ID"   => tenant_id,
            }
            response = client.delete("/v1/snapshot/local", headers: headers)
            client.close rescue nil
            context.put_status(response.status_code).json({"status" => "ok"}).halt
          rescue ex
            context.put_status(502).json({"error" => "backend unreachable: #{ex.message}"}).halt
          end
        end
      end

      # GET /v1/customers/:name/directory/snapshot/local
      # Fetches the portal-managed local users encrypted snapshot blob.
      # Returns {"blob": "<base64>"} or 204 if no local snapshot yet.
      class GetLocalSnapshot
        include Grip::Controllers::HTTP
        include DirectoryHelper
        include DirectoryHTTP

        def get(context : Context) : Context
          proxy_blob_get(context, "/v1/snapshot/local")
        end
      end

      # POST /v1/customers/:name/directory/snapshot/local
      # Accepts {"blob": "<base64>", "recipient": "<age public key>"} and
      # PUTs the encrypted blob to the customer's backend as the local snapshot.
      # This is the only blob the portal is allowed to write.
      class PushLocalSnapshot
        include Grip::Controllers::HTTP
        include DirectoryHelper
        include DirectoryHTTP

        def post(context : Context) : Context
          proxy_blob_put(context, "/v1/snapshot/local")
        end
      end

      # Legacy alias kept for backward compatibility. Previously wrote to the
      # cloud blob (/v1/syncer/sync) - now redirected to the local blob so that
      # manually-added users are preserved across syncer cycles.
      # Remove once all portal clients are on the new paths.
      GetDirectorySnapshot = GetCloudSnapshot

      class PushDirectorySnapshot
        include Grip::Controllers::HTTP
        include DirectoryHelper
        include DirectoryHTTP

        def post(context : Context) : Context
          proxy_blob_put(context, "/v1/snapshot/local")
        end
      end

      # GET /v1/customers/:name/directory/authz-config
      # Proxies to the customer's backend to fetch host authorization config.
      class GetAuthzConfig
        include Grip::Controllers::HTTP
        include DirectoryHelper
        include DirectoryHTTP

        def get(context : Context) : Context
          name = context.fetch_path_params["name"]
          result = resolve_context(context, name)
          return context unless result

          customer, tenant_id, primary_node = result
          hostname = "#{customer.name}.#{Ops.config.backend_domain}"

          begin
            status_code, body = backend_get(primary_node.ip, hostname,
              "/v1/snapshot/authz-config", customer.hmac_secret, tenant_id)
            if status_code == 200
              context.put_status(200).json(JSON.parse(body)).halt
            else
              context.put_status(502).json({"error" => "backend returned HTTP #{status_code}"}).halt
            end
          rescue ex
            context.put_status(502).json({"error" => "backend unreachable: #{ex.message}"}).halt
          end
        end
      end

      # PUT /v1/customers/:name/directory/authz-config
      # Proxies to the customer's backend to update host authorization config.
      # Body: {"enforce_group_memberships": bool, "host_group_rules": [{"group": str, "host": str}]}
      class PutAuthzConfig
        include Grip::Controllers::HTTP
        include DirectoryHelper
        include DirectoryHTTP

        def put(context : Context) : Context
          name = context.fetch_path_params["name"]
          result = resolve_context(context, name)
          return context unless result

          customer, tenant_id, primary_node = result
          hostname = "#{customer.name}.#{Ops.config.backend_domain}"

          body = context.request.body.try(&.gets_to_end) || ""
          begin
            JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON: #{ex.message}"}).halt
          end

          begin
            status_code, response_body = backend_json_put(
              primary_node.ip, hostname,
              "/v1/snapshot/authz-config",
              customer.hmac_secret, tenant_id, body,
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
      end
    end
  end
end
