require "grip"
require "json"
require "../models/customer"
require "../models/customer_account"
require "../models/provision_job"

module Dirless
  module Ops
    module Controllers
      ALPHA = ('a'..'z').to_a

      class PortalRegister
        include Grip::Controllers::HTTP

        def post(context : Context) : Context
          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON: #{ex.message}"}).halt
          end

          email = parsed["email"]?.try(&.as_s).to_s.strip.downcase
          password = parsed["password"]?.try(&.as_s).to_s
          company = parsed["company"]?.try(&.as_s).to_s.strip

          errors = {} of String => String
          errors["email"] = "Required" if email.empty?
          errors["email"] = "Invalid email" unless email.includes?("@") && email.includes?(".")
          errors["password"] = "Required" if password.empty?
          errors["password"] = "Must be at least 12 characters" if !password.empty? && password.size < 12
          errors["company"] = "Required" if company.empty?

          unless errors.empty?
            return context.put_status(422).json({"error" => errors.map { |f, m| "#{f}: #{m}" }.join("; "), "fields" => errors}).halt
          end

          if CustomerAccount.where(email: email).exists?
            return context.put_status(409).json({"error" => "email already registered", "fields" => {"email" => "An account with this email already exists"}}).halt
          end

          # Generate customer name: 12 random lowercase letters + "-" + (max port + 1, starting at 5000)
          random_part = Array.new(12) { ALPHA.sample }.join
          max_port = Customer.all.map { |c| c.port }.select { |p| p >= 5000 }.max?
          next_port = max_port ? max_port + 1 : 5000
          customer_name = "#{random_part}-#{next_port}"

          hmac_secret = Random::Secure.hex(32)

          customer = Customer.new(
            name: customer_name,
            hmac_secret: hmac_secret,
            label: company,
          )

          unless customer.save
            return context.put_status(422).json({"error" => customer.errors.map(&.message).join(", ")}).halt
          end

          account = CustomerAccount.new(
            email: email,
            password_hash: CustomerAccount.hash_password(password),
            customer_name: customer_name,
            company: company,
            provisioned: false,
          )

          unless account.save
            customer.destroy
            return context.put_status(422).json({"error" => account.errors.map(&.message).join(", ")}).halt
          end

          # Queue a provision job for the deployer to pick up
          job = ProvisionJob.new(customer_name: customer_name, status: "pending")
          job.save

          context.put_status(201).json(account.to_response).halt
        end
      end

      class PortalLogin
        include Grip::Controllers::HTTP

        def post(context : Context) : Context
          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON: #{ex.message}"}).halt
          end

          email = parsed["email"]?.try(&.as_s).to_s.strip.downcase
          password = parsed["password"]?.try(&.as_s).to_s

          account = CustomerAccount.find_by(email: email)

          unless account && account.verify_password(password)
            return context.put_status(401).json({"error" => "Invalid email or password"}).halt
          end

          context.put_status(200).json(account.to_response).halt
        end
      end
    end
  end
end
