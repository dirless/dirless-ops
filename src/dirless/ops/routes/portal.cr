require "grip"
require "json"
require "../models/customer"
require "../models/provision_job"

module Dirless
  module Ops
    module Controllers
      ALPHA = ('a'..'z').to_a

      class PortalRegister
        include Grip::Controllers::HTTP

        # ameba:disable Metrics/CyclomaticComplexity
        def post(context : Context) : Context
          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON: #{ex.message}"}).halt
          end

          email          = parsed["email"]?.try(&.as_s).to_s.strip.downcase
          password       = parsed["password"]?.try(&.as_s).to_s
          first_name     = parsed["first_name"]?.try(&.as_s).to_s.strip
          last_name      = parsed["last_name"]?.try(&.as_s).to_s.strip
          company        = parsed["company"]?.try(&.as_s).to_s.strip
          country        = parsed["country"]?.try(&.as_s).to_s.strip
          # Admin-only override: skip email verification (safe — all /v1 routes require API key).
          # Accepts JSON boolean true or string "true".
          skip_verify = parsed["email_verified"]?.try { |v| v.as_bool? || v.as_s? == "true" } || false

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
            return context.put_status(422).json({"error" => errors.map { |field, msg| "#{field}: #{msg}" }.join("; "), "fields" => errors}).halt
          end

          if Customer.where(email: email).exists?
            return context.put_status(409).json({"error" => "email already registered", "fields" => {"email" => "An account with this email already exists"}}).halt
          end

          # Wrap all writes in a transaction so customer + job are created atomically.
          db = Granite::Connections["sqlite"].not_nil![:writer].database
          customer_name = ""
          verify_token = ""
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
            verify_token = Random::Secure.hex(32)

            customer = Customer.new(
              name: customer_name,
              hmac_secret: hmac_secret,
              # Non-AWS customers have no aws_account_id to derive tenant_id from,
              # so generate one now and persist it. The directory feature and the
              # agent config both rely on this being stable.
              tenant_id: "aws___" + Random::Secure.hex(32),
              email: email,
              password_hash: Customer.hash_password(password),
              first_name: first_name,
              last_name: last_name,
              company: company,
              country: country,
              provisioned: false,
              email_verified: skip_verify,
              email_verify_token: skip_verify ? nil : verify_token,
              beta_customer: false,
            )

            unless customer.save
              db.exec("ROLLBACK")
              return context.put_status(422).json({"error" => customer.errors.map(&.message).join(", ")}).halt
            end

            # Queue a provision job for the deployer to pick up
            job = ProvisionJob.new(customer_name: customer_name, status: "pending")
            job.save

            db.exec("COMMIT")
            Ops.notifier.welcome(email, company, customer_name)
            Ops.notifier.verify_email(email, verify_token) unless skip_verify
          rescue ex
            db.exec("ROLLBACK") rescue nil
            Log.error { "Registration failed for #{email}: #{ex.class}: #{ex.message}" }
            Ops.notifier.registration_error(email, ex)
            return context.put_status(503).json({"error" => "Service temporarily unavailable, please try again"}).halt
          end

          if stripe = Ops.stripe_client
            begin
              beta = Ops.config.beta_mode
              meta = {"customer_name" => customer_name}
              meta["beta"] = "true" if beta
              stripe_id = stripe.create_customer(
                email: email,
                name: "#{first_name} #{last_name}",
                metadata: meta
              )
              customer.stripe_customer_id = stripe_id
              customer.beta_customer = beta
              customer.save
            rescue ex
              Log.error { "Stripe customer creation failed for #{email}: #{ex.message}" }
            end
          end

          context.put_status(201).json(customer.to_response).halt
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

          customer = Customer.find_by(name: customer_name)
          return context.put_status(404).json({"error" => "account not found"}).halt unless customer

          stripe_customer_id = customer.stripe_customer_id
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

          customer = Customer.find_by(name: result[:customer_name])
          return context.put_status(404).json({"error" => "account not found"}).halt unless customer

          customer.plan = result[:plan]
          customer.save

          context.put_status(200).json(customer.to_response).halt
        end
      end

      class PortalVerifyEmail
        include Grip::Controllers::HTTP

        def get(context : Context) : Context
          token = context.request.query_params["token"]?.to_s.strip
          return context.put_status(400).json({"error" => "missing token"}).halt if token.empty?

          customer = Customer.find_by(email_verify_token: token)
          return context.put_status(404).json({"error" => "invalid or expired token"}).halt unless customer

          customer.email_verified = true
          customer.email_verify_token = nil
          unless customer.save
            return context.put_status(422).json({"error" => "could not verify email"}).halt
          end

          context.put_status(200).json(customer.to_response).halt
        end
      end

      class PortalResendVerification
        include Grip::Controllers::HTTP

        RESEND_COOLDOWN = 60.seconds

        def post(context : Context) : Context
          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON"}).halt
          end

          customer_name = parsed["customer_name"]?.try(&.as_s).to_s.strip
          return context.put_status(400).json({"error" => "customer_name required"}).halt if customer_name.empty?

          customer = Customer.find_by(name: customer_name)
          return context.put_status(404).json({"error" => "account not found"}).halt unless customer
          return context.put_status(200).json({"ok" => true, "message" => "already verified"}).halt if customer.email_verified

          # Rate limit: don't resend if updated recently
          if updated = customer.updated_at
            if Time.utc - updated < RESEND_COOLDOWN
              return context.put_status(429).json({"error" => "please wait before requesting another verification email"}).halt
            end
          end

          token = Random::Secure.hex(32)
          customer.email_verify_token = token
          customer.save

          email = customer.email || ""
          Ops.notifier.verify_email(email, token) unless email.empty?

          context.put_status(200).json({"ok" => true}).halt
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

          customer = Customer.find_by(email: email)

          if customer && customer.password_hash
            valid = customer.verify_password(password)
          else
            # Burn the same amount of CPU time as a real verify to prevent
            # attackers from distinguishing "email not found" by response timing.
            Crypto::Bcrypt::Password.new(DUMMY_HASH).verify(password)
            valid = false
          end

          unless valid
            return context.put_status(401).json({"error" => "Invalid email or password"}).halt
          end

          # customer is non-nil here: the `unless valid` guard above returns early.
          context.put_status(200).json(customer.as(Customer).to_response).halt
        end
      end
    end
  end
end
