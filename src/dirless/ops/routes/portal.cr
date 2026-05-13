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

          email      = parsed["email"]?.try(&.as_s).to_s.strip.downcase
          password   = parsed["password"]?.try(&.as_s).to_s
          first_name = parsed["first_name"]?.try(&.as_s).to_s.strip
          last_name  = parsed["last_name"]?.try(&.as_s).to_s.strip
          company    = parsed["company"]?.try(&.as_s).to_s.strip
          country    = parsed["country"]?.try(&.as_s).to_s.strip

          errors = {} of String => String
          errors["email"]      = "Required"                       if email.empty?
          errors["email"]      = "Invalid email"                  unless email.empty? || email.matches?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
          errors["password"]   = "Required"                       if password.empty?
          errors["password"]   = "Must be at least 12 characters" if !password.empty? && password.size < 12
          errors["first_name"] = "Required"                       if first_name.empty?
          errors["last_name"]  = "Required"                       if last_name.empty?
          errors["company"]    = "Required"                       if company.empty?
          errors["country"]    = "Required"                       if country.empty?

          unless errors.empty?
            return context.put_status(422).json({"error" => errors.map { |f, m| "#{f}: #{m}" }.join("; "), "fields" => errors}).halt
          end

          if CustomerAccount.where(email: email).exists?
            return context.put_status(409).json({"error" => "email already registered", "fields" => {"email" => "An account with this email already exists"}}).halt
          end

          # Wrap all writes in a transaction so customer + account + job
          # are created atomically (no partial state on failure).
          db = Granite::Connections["sqlite"].not_nil![:writer].database
          begin
            db.exec("BEGIN IMMEDIATE")

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
              first_name: first_name,
              last_name: last_name,
              company: company,
              country: country,
              provisioned: false,
              beta_customer: false,
            )

            unless account.save
              db.exec("ROLLBACK")
              return context.put_status(422).json({"error" => account.errors.map(&.message).join(", ")}).halt
            end

            # Queue a provision job for the deployer to pick up
            job = ProvisionJob.new(customer_name: customer_name, status: "pending")
            job.save

            db.exec("COMMIT")
            Ops.notifier.welcome(email, company, customer_name)
          rescue ex
            db.exec("ROLLBACK") rescue nil
            return context.put_status(503).json({"error" => "Service temporarily unavailable, please try again"}).halt
          end

          if (stripe = Ops.stripe_client)
            begin
              beta = Ops.config.beta_mode
              meta = {"customer_name" => customer_name}
              meta["beta"] = "true" if beta
              stripe_id = stripe.create_customer(
                email: email,
                name: "#{first_name} #{last_name}",
                metadata: meta
              )
              account.stripe_customer_id = stripe_id
              account.beta_customer = beta
              account.save
            rescue ex
              Log.error { "Stripe customer creation failed for #{email}: #{ex.message}" }
            end
          end

          context.put_status(201).json(account.to_response).halt
        end
      end

      class PortalCreateCheckout
        include Grip::Controllers::HTTP

        VALID_PLANS = {"starter", "growth", "scale"}

        def post(context : Context) : Context
          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON"}).halt
          end

          customer_name = parsed["customer_name"]?.try(&.as_s).to_s.strip
          plan          = parsed["plan"]?.try(&.as_s).to_s.strip.downcase
          success_url   = parsed["success_url"]?.try(&.as_s).to_s.strip
          cancel_url    = parsed["cancel_url"]?.try(&.as_s).to_s.strip

          unless VALID_PLANS.includes?(plan)
            return context.put_status(422).json({"error" => "invalid plan"}).halt
          end

          stripe = Ops.stripe_client
          return context.put_status(503).json({"error" => "payments not configured"}).halt unless stripe

          account = CustomerAccount.find_by(customer_name: customer_name)
          return context.put_status(404).json({"error" => "account not found"}).halt unless account

          stripe_customer_id = account.stripe_customer_id
          return context.put_status(422).json({"error" => "no stripe customer on record"}).halt unless stripe_customer_id

          beta    = Ops.config.beta_mode
          price_key = beta ? "#{plan}_beta" : "#{plan}_full"
          price_id  = Ops.config.stripe_prices[price_key]?
          return context.put_status(503).json({"error" => "price not configured for #{price_key}"}).halt unless price_id

          begin
            url = stripe.create_checkout_session(
              customer_id:   stripe_customer_id,
              price_id:      price_id,
              customer_name: customer_name,
              plan:          plan,
              success_url:   success_url,
              cancel_url:    cancel_url
            )
            context.put_status(200).json({"url" => url}).halt
          rescue ex
            Log.error { "Stripe checkout session creation failed: #{ex.message}" }
            context.put_status(502).json({"error" => "failed to create checkout session"}).halt
          end
        end
      end

      class PortalVerifyCheckout
        include Grip::Controllers::HTTP

        def get(context : Context) : Context
          session_id = context.fetch_path_params["session_id"]

          stripe = Ops.stripe_client
          return context.put_status(503).json({"error" => "payments not configured"}).halt unless stripe

          begin
            result = stripe.retrieve_checkout_session(session_id)
          rescue ex
            Log.error { "Stripe session retrieval failed: #{ex.message}" }
            return context.put_status(502).json({"error" => "failed to retrieve session"}).halt
          end

          unless result[:payment_status] == "paid"
            return context.put_status(402).json({"error" => "payment not completed"}).halt
          end

          account = CustomerAccount.find_by(customer_name: result[:customer_name])
          return context.put_status(404).json({"error" => "account not found"}).halt unless account

          account.plan = result[:plan]
          account.save

          context.put_status(200).json(account.to_response).halt
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
