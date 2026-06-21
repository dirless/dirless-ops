require "grip"
require "json"
require "digest/sha256"
require "../models/customer"
require "../models/ssh_bootstrap_token"
require "../models/ssh_user_registration"

module Dirless
  module Ops
    module Controllers
      # POST /v1/portal/bootstrap/request
      # Public endpoint (no API key) — the customer_name + email pair is the credential.
      # Generates a one-time magic-link token and emails it. Always returns 200 to
      # prevent email enumeration: the caller cannot distinguish "account found" from
      # "account not found" by the response.
      class BootstrapRequest
        include Grip::Controllers::HTTP

        BOOTSTRAP_TOKEN_TTL = 10.minutes
        RESEND_COOLDOWN     = 60.seconds

        VALID_SSH_KEY_TYPES = %w[
          ssh-ed25519
          ssh-rsa
          ecdsa-sha2-nistp256
          ecdsa-sha2-nistp384
          ecdsa-sha2-nistp521
          sk-ssh-ed25519@openssh.com
          sk-ecdsa-sha2-nistp256@openssh.com
        ]

        def post(context : Context) : Context
          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON"}).halt
          end

          email            = parsed["email"]?.try(&.as_s).to_s.strip.downcase
          age_public_key   = parsed["age_public_key"]?.try(&.as_s).to_s.strip
          ssh_public_key   = parsed["ssh_public_key"]?.try(&.as_s).to_s.strip
          customer_name    = parsed["customer_name"]?.try(&.as_s).to_s.strip
          provided_username = parsed["username"]?.try(&.as_s).to_s.strip.downcase

          return context.put_status(422).json({"error" => "email required"}).halt if email.empty?
          return context.put_status(422).json({"error" => "age_public_key required"}).halt if age_public_key.empty?
          return context.put_status(422).json({"error" => "ssh_public_key required"}).halt if ssh_public_key.empty?
          return context.put_status(422).json({"error" => "username required"}).halt if provided_username.empty?
          unless provided_username.match(/\A[a-z0-9_-]+\z/)
            return context.put_status(422).json({"error" => "username may only contain lowercase letters, digits, hyphens, and underscores"}).halt
          end

          # Validate age public key format.
          unless age_public_key.starts_with?("age1")
            return context.put_status(422).json({"error" => "age_public_key must start with 'age1'"}).halt
          end

          # Validate SSH public key format — must have a known type prefix and a base64 body.
          unless valid_ssh_public_key?(ssh_public_key)
            return context.put_status(422).json({"error" => "ssh_public_key format invalid"}).halt
          end

          # Look up the customer. Always return 200 regardless of outcome (M1 — no enumeration).
          customer = find_customer(email, customer_name)
          unless customer
            # No account found — return success silently to prevent email enumeration.
            return context.put_status(200).json({
              "ok"      => true,
              "message" => "If that email is associated with a Dirless account, you will receive a registration link shortly.",
            }).halt
          end

          # Rate limit: at most one magic link per email per RESEND_COOLDOWN window.
          existing = SshBootstrapToken.find_by(customer_name: customer.name, email: email)
          if existing && !existing.expired? && existing.used == false
            if created = existing.created_at
              if Time.utc - created < RESEND_COOLDOWN
                return context.put_status(429).json({
                  "error" => "Please wait before requesting another registration link.",
                }).halt
              end
            end
          end

          username = provided_username

          token = Random::Secure.hex(32)
          record = SshBootstrapToken.new(
            token:          token,
            customer_name:  customer.name,
            username:       username,
            email:          email,
            age_public_key: age_public_key,
            ssh_public_key: ssh_public_key,
            used:           false,
            expires_at:     Time.utc + BOOTSTRAP_TOKEN_TTL,
          )
          unless record.save
            return context.put_status(503).json({"error" => "service temporarily unavailable"}).halt
          end

          Ops.notifier.ssh_bootstrap_magic_link(email, username, token)

          context.put_status(200).json({
            "ok"      => true,
            "message" => "If that email is associated with a Dirless account, you will receive a registration link shortly.",
          }).halt
        end

        private def find_customer(email : String, customer_name : String) : Customer?
          if customer_name.empty?
            Customer.find_by(email: email)
          else
            Customer.find_by(name: customer_name)
          end
        end

        private def valid_ssh_public_key?(key : String) : Bool
          parts = key.strip.split(/\s+/)
          return false unless parts.size >= 2
          return false unless VALID_SSH_KEY_TYPES.includes?(parts[0])
          begin
            decoded = Base64.decode(parts[1])
            decoded.size >= 16  # minimum plausible key body
          rescue
            false
          end
        end
      end

      # GET /v1/portal/bootstrap/confirm?token=...
      # Public endpoint — the token is the credential.
      # Atomically claims the token (BEGIN IMMEDIATE transaction), upserts the
      # SshUserRegistration, and marks the token used. The whole sequence is
      # wrapped in a write-lock transaction to prevent double-spend races (H1).
      class BootstrapConfirm
        include Grip::Controllers::HTTP

        def get(context : Context) : Context
          token = context.request.query_params["token"]?.to_s.strip
          return context.put_status(400).json({"error" => "missing token"}).halt if token.empty?

          db = Granite::Connections["sqlite"].not_nil![:writer].database

          result_tuple = begin
            db.exec("BEGIN IMMEDIATE")

            # Look up the token inside the write lock — prevents two concurrent
            # confirms from both seeing used=false.
            row = db.query_one?(
              "SELECT id, customer_name, username, email, age_public_key, ssh_public_key, used, expires_at FROM ssh_bootstrap_tokens WHERE token = ?",
              token,
              as: {Int64, String, String, String, String, String, Bool, String?}
            )

            unless row
              db.exec("ROLLBACK")
              return context.put_status(404).json({"error" => "invalid or expired token"}).halt
            end

            id, cust_name, username, email, age_pub, ssh_pub, used, expires_at_str = row

            if used
              db.exec("ROLLBACK")
              return context.put_status(410).json({"error" => "token already used"}).halt
            end

            if exp_str = expires_at_str
              expires_at = Time.parse(exp_str, "%Y-%m-%d %H:%M:%S", Time::Location::UTC) rescue Time.unix(0)
              if Time.utc > expires_at
                db.exec("ROLLBACK")
                return context.put_status(410).json({"error" => "token expired"}).halt
              end
            end

            # Mark used before touching the registration so any concurrent request
            # sees used=true even if reg.save is slow.
            db.exec("UPDATE ssh_bootstrap_tokens SET used = 1 WHERE id = ?", id)
            db.exec("COMMIT")

            {cust_name, username, email, age_pub, ssh_pub}
          rescue ex
            db.exec("ROLLBACK") rescue nil
            Log.error { "bootstrap confirm transaction failed: #{ex.message}" }
            return context.put_status(503).json({"error" => "service temporarily unavailable"}).halt
          end

          cust_name, username, email, age_pub, ssh_pub = result_tuple

          # Reject if this email is already registered under a different username.
          existing_for_email = SshUserRegistration.find_by(customer_name: cust_name, email: email)
          if existing_for_email && existing_for_email.username != username
            return context.put_status(409).json({
              "error" => "This email is already registered under a different username. Contact your administrator.",
            }).halt
          end

          # Upsert the user registration outside the transaction — Granite ORM handles this.
          reg = SshUserRegistration.find_by(customer_name: cust_name, username: username) ||
                SshUserRegistration.new(customer_name: cust_name, username: username)
          reg.email          = email
          reg.age_public_key = age_pub
          reg.ssh_public_key = ssh_pub
          unless reg.save
            return context.put_status(503).json({"error" => "could not save registration"}).halt
          end

          context.put_status(200).json({
            "ok"            => true,
            "customer_name" => cust_name,
            "username"      => username,
            "message"       => "SSH certificate registration complete. You can now run 'dirless-connect ssh login'.",
          }).halt
        end

        private Log = ::Log.for("dirless.ops.bootstrap")
      end
    end
  end
end
