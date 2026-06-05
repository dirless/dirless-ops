require "grip"
require "json"
require "../models/customer"

module Dirless
  module Ops
    module Controllers
      class ListCustomers
        include Grip::Controllers::HTTP

        def get(context : Context) : Context
          customers = Customer.all
          context.put_status(200).json(customers.map(&.to_response)).halt
        end
      end

      class CreateCustomer
        include Grip::Controllers::HTTP

        def post(context : Context) : Context
          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON: #{ex.message}"}).halt
          end

          name = parsed["name"]?.try(&.as_s)
          hmac_secret = parsed["hmac_secret"]?.try(&.as_s)

          unless name && hmac_secret
            return context.put_status(422).json({"error" => "name and hmac_secret are required"}).halt
          end

          errors = {} of String => String

          unless name =~ /\A[a-z]{12}-\d+\z/
            errors["name"] = "Must be 12 lowercase letters, a dash, then a port number (e.g. ewmilnqiuhxu-5000)"
          end

          port = name.split("-").last.to_i?
          if port && (port < 1024 || port > 59999)
            errors["name"] = "Port must be between 1024 and 59999"
          end

          unless hmac_secret =~ /\A[0-9a-f]{64}\z/
            errors["hmac_secret"] = "Must be exactly 64 lowercase hex characters"
          end

          unless errors.empty?
            return context.put_status(422).json({"error" => errors.map { |field, message| "#{field}: #{message}" }.join("; "), "fields" => errors}).halt
          end

          if Customer.where(name: name).exists?
            return context.put_status(409).json({"error" => "customer already exists", "fields" => {"name" => "A customer with this name already exists"}}).halt
          end

          explicit_tenant_id = parsed["tenant_id"]?.try(&.as_s)
          aws_id = parsed["aws_account_id"]?.try(&.as_s)

          # For non-AWS customers (no aws_account_id) generate a stable tenant_id
          # now so the directory feature always has one to work with.
          # AWS customers derive theirs at runtime from aws_account_id + hmac_secret.
          derived_tenant_id = if explicit_tenant_id
                                explicit_tenant_id
                              elsif aws_id.nil? || aws_id.empty?
                                "aws___" + Random::Secure.hex(32)
                              end

          customer = Customer.new(
            name: name,
            hmac_secret: hmac_secret,
            label: parsed["label"]?.try(&.as_s),
            aws_account_id: aws_id,
            notes: parsed["notes"]?.try(&.as_s),
            tenant_id: derived_tenant_id,
          )

          unless customer.save
            return context.put_status(422).json({"error" => customer.errors.map(&.message).join(", ")}).halt
          end

          context.put_status(201).json(customer.to_response).halt
        end
      end

      class GetCustomer
        include Grip::Controllers::HTTP

        def get(context : Context) : Context
          name = context.fetch_path_params["name"]
          customer = Customer.find_by(name: name)

          unless customer
            return context.put_status(404).json({"error" => "customer not found"}).halt
          end

          context.put_status(200).json(customer.to_response).halt
        end
      end

      class UpdateCustomer
        include Grip::Controllers::HTTP

        def patch(context : Context) : Context
          name = context.fetch_path_params["name"]
          customer = Customer.find_by(name: name)

          unless customer
            return context.put_status(404).json({"error" => "customer not found"}).halt
          end

          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON: #{ex.message}"}).halt
          end

          parsed["label"]?.try { |v| customer.label = v.as_s? }
          parsed["email"]?.try { |v| customer.email = v.as_s? }
          parsed["company"]?.try { |v| customer.company = v.as_s? }
          parsed["hmac_secret"]?.try { |v| v.as_s?.try { |str| customer.hmac_secret = str } }
          parsed["aws_account_id"]?.try { |v| customer.aws_account_id = v.as_s? }
          parsed["notes"]?.try { |v| customer.notes = v.as_s? }
          parsed["tenant_id"]?.try { |v| customer.tenant_id = v.as_s? }
          parsed["password"]?.try { |v| v.as_s?.try { |str| customer.password_hash = Customer.hash_password(str) } }

          unless customer.save
            return context.put_status(422).json({"error" => customer.errors.map(&.message).join(", ")}).halt
          end

          context.put_status(200).json(customer.to_response).halt
        end
      end

      class DeleteCustomer
        include Grip::Controllers::HTTP

        def delete(context : Context) : Context
          name = context.fetch_path_params["name"]
          customer = Customer.find_by(name: name)

          unless customer
            return context.put_status(404).json({"error" => "customer not found"}).halt
          end

          email = customer.email
          company = customer.company || name
          customer.destroy
          if email
            Ops.notifier.account_deleted(email, company)
          end
          queue_deprovision(name)
          context.put_status(204).halt
        end

        private def queue_deprovision(customer_name : String)
          spool_dir = Ops.config.deprovision_spool_dir
          Dir.mkdir_p(spool_dir)
          tmp = File.join(spool_dir, "#{customer_name}.json.tmp")
          final = File.join(spool_dir, "#{customer_name}.json")
          File.write(tmp, {"customer_name" => customer_name}.to_json)
          File.rename(tmp, final)
        rescue ex
          Log.error { "Failed to queue deprovision for #{customer_name}: #{ex.message}" }
        end
      end
    end
  end
end
