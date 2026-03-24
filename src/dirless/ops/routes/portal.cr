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
          errors["email"] = "Invalid email" unless email.empty? || email.matches?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
          errors["password"] = "Required" if password.empty?
          errors["password"] = "Must be at least 12 characters" if !password.empty? && password.size < 12
          errors["company"] = "Required" if company.empty?

          unless errors.empty?
            return context.put_status(422).json({"error" => errors.map { |f, m| "#{f}: #{m}" }.join("; "), "fields" => errors}).halt
          end

          if CustomerAccount.where(email: email).exists?
            return context.put_status(409).json({"error" => "email already registered", "fields" => {"email" => "An account with this email already exists"}}).halt
          end

          # Wrap all writes in a transaction so customer + account + job
          # are created atomically (no partial state on failure).
          db = Granite::Connections["sqlite"].not_nil![:writer].database
          db.exec("BEGIN IMMEDIATE")

          begin
            # Atomic port allocation: SELECT MAX inside the transaction
            # prevents two concurrent registrations from getting the same port.
            # BEGIN IMMEDIATE acquires a write lock immediately.
            random_part = Array.new(12) { ALPHA.sample }.join
            max_port_result = db.scalar("SELECT MAX(CAST(SUBSTR(name, INSTR(name, '-') + 1) AS INTEGER)) FROM customers WHERE CAST(SUBSTR(name, INSTR(name, '-') + 1) AS INTEGER) >= 5000")
            next_port = max_port_result.is_a?(Int64) ? max_port_result.to_i + 1 : 5000
            customer_name = "#{random_part}-#{next_port}"

            hmac_secret = Random::Secure.hex(32)

            customer = Customer.new(
              name: customer_name,
              hmac_secret: hmac_secret,
              label: company,
            )

            unless customer.save
              db.exec("ROLLBACK")
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
              db.exec("ROLLBACK")
              return context.put_status(422).json({"error" => account.errors.map(&.message).join(", ")}).halt
            end

            # Queue a provision job for the deployer to pick up
            job = ProvisionJob.new(customer_name: customer_name, status: "pending")
            job.save

            db.exec("COMMIT")
          rescue ex
            db.exec("ROLLBACK") rescue nil
            raise ex
          end

          context.put_status(201).json(account.to_response).halt
        end
      end

      class PortalLogin
        include Grip::Controllers::HTTP

        # Pre-computed dummy hash so that login attempts for non-existent emails
        # still spend time in bcrypt, preventing timing-based email enumeration.
        DUMMY_HASH = Crypto::Bcrypt::Password.create("dummy-timing-equalizer", cost: 12).to_s

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

          if account
            valid = account.verify_password(password)
          else
            # Burn the same amount of CPU time as a real verify to prevent
            # attackers from distinguishing "email not found" by response timing.
            Crypto::Bcrypt::Password.new(DUMMY_HASH).verify(password)
            valid = false
          end

          unless valid
            return context.put_status(401).json({"error" => "Invalid email or password"}).halt
          end

          context.put_status(200).json(account.not_nil!.to_response).halt
        end
      end
    end
  end
end
