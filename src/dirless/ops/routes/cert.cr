require "grip"
require "json"
require "base64"
require "openssl"
require "age-crystal"
require "../models/customer"
require "../models/ssh_user_registration"
require "../models/ssh_challenge"

module Dirless
  module Ops
    module Controllers
      # POST /v1/portal/cert/challenge
      # Public endpoint (no API key) — authenticated by (customer_name, username) pair
      # which must resolve to a registered user.
      # Generates a random nonce, encrypts it to the user's age public key (only the user
      # can decrypt it), stores SHA256(nonce) — never the plaintext — and returns the
      # encrypted nonce. The plaintext nonce never touches the database.
      class CertChallenge
        include Grip::Controllers::HTTP

        CHALLENGE_TTL = 60.seconds

        def post(context : Context) : Context
          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON"}).halt
          end

          customer_name = parsed["customer_name"]?.try(&.as_s).to_s.strip
          username      = parsed["username"]?.try(&.as_s).to_s.strip

          return context.put_status(422).json({"error" => "customer_name required"}).halt if customer_name.empty?
          return context.put_status(422).json({"error" => "username required"}).halt if username.empty?

          reg = SshUserRegistration.find_by(customer_name: customer_name, username: username)
          return context.put_status(404).json({
            "error" => "user not registered — run dirless-connect ssh register first",
          }).halt unless reg

          # Generate 32-byte random nonce, hex-encoded: 256 bits of entropy.
          nonce_plaintext = Random::Secure.hex(32)
          nonce_hash = sha256(nonce_plaintext)

          # Encrypt the nonce to the user's age public key.
          nonce_encrypted = begin
            recipient = Age::PublicKey.new(reg.age_public_key)
            Base64.strict_encode(Age.encrypt(nonce_plaintext, recipient))
          rescue ex
            Log.error { "age encrypt failed for #{username}@#{customer_name}: #{ex.message}" }
            return context.put_status(503).json({"error" => "could not generate challenge"}).halt
          end

          # Delete any previous challenge for this user before inserting a fresh one.
          SshChallenge.where(customer_name: customer_name, username: username).delete rescue nil

          challenge = SshChallenge.new(
            customer_name: customer_name,
            username:      username,
            nonce_hash:    nonce_hash,
            expires_at:    Time.utc + CHALLENGE_TTL,
          )
          unless challenge.save
            return context.put_status(503).json({"error" => "could not store challenge"}).halt
          end

          context.put_status(200).json({"nonce_encrypted" => nonce_encrypted}).halt
        end

        private def sha256(s : String) : String
          OpenSSL::Digest.new("SHA256").update(s).hexfinal
        end

        private Log = ::Log.for("dirless.ops.cert")
      end

      # POST /v1/portal/cert/sign
      # Public endpoint (no API key) — authenticated by the challenge-response flow.
      # The client must decrypt the encrypted nonce (proving possession of the age
      # private key) and submit the plaintext. The server computes SHA256(submitted)
      # and atomically DELETEs the challenge row matching that hash — only one concurrent
      # request can succeed (H2). If the destroy races, rows_affected = 0 → 401.
      class CertSign
        include Grip::Controllers::HTTP

        def post(context : Context) : Context
          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON"}).halt
          end

          customer_name = parsed["customer_name"]?.try(&.as_s).to_s.strip
          username      = parsed["username"]?.try(&.as_s).to_s.strip
          nonce         = parsed["nonce"]?.try(&.as_s).to_s.strip

          return context.put_status(422).json({"error" => "customer_name required"}).halt if customer_name.empty?
          return context.put_status(422).json({"error" => "username required"}).halt if username.empty?
          return context.put_status(422).json({"error" => "nonce required"}).halt if nonce.empty?

          submitted_hash = sha256(nonce)

          # Atomic nonce consume: DELETE only succeeds if the hash matches AND the
          # challenge has not already been claimed by a concurrent request. This makes
          # the nonce check and the consume a single, non-raceable operation (H2+M2).
          db = Granite::Connections["sqlite"].not_nil![:writer].database
          result = db.exec(
            "DELETE FROM ssh_challenges WHERE customer_name = ? AND username = ? AND nonce_hash = ?",
            customer_name, username, submitted_hash
          )

          if result.rows_affected == 0
            # Either no challenge exists, the nonce was wrong, or a concurrent request
            # already consumed it. All map to the same 401 — no oracle for which.
            return context.put_status(401).json({
              "error" => "invalid or expired challenge — call /cert/challenge first",
            }).halt
          end

          customer = Customer.find_by(name: customer_name)
          return context.put_status(404).json({"error" => "customer not found"}).halt unless customer

          ca_private_key = customer.ca_private_key
          return context.put_status(503).json({
            "error" => "SSH CA not yet generated — provisioning may still be in progress",
          }).halt unless ca_private_key

          reg = SshUserRegistration.find_by(customer_name: customer_name, username: username)
          return context.put_status(404).json({"error" => "user registration not found"}).halt unless reg

          ttl_seconds = (customer.cert_ttl_seconds || 28800_i64).to_i64

          certificate = sign_certificate(
            ca_private_key: ca_private_key,
            ssh_public_key: reg.ssh_public_key,
            username:       username,
            customer_name:  customer_name,
            ttl_seconds:    ttl_seconds,
          )

          case certificate
          in String
            context.put_status(200).json({
              "certificate"  => certificate,
              "ttl_seconds"  => ttl_seconds,
              "valid_before" => (Time.utc + ttl_seconds.seconds).to_rfc3339,
            }).halt
          in Nil
            context.put_status(503).json({"error" => "certificate signing failed"}).halt
          end
        end

        private def sign_certificate(ca_private_key : String, ssh_public_key : String,
                                     username : String, customer_name : String,
                                     ttl_seconds : Int64) : String?
          SSH::Certificate.sign(
            ca_pem:               ca_private_key,
            user_public_key_line: ssh_public_key,
            key_id:               "#{username}@#{customer_name}",
            principals:           [username],
            ttl_seconds:          ttl_seconds,
          )
        rescue ex
          Log.error { "sign_certificate error: #{ex.message}" }
          nil
        end

        private def sha256(s : String) : String
          OpenSSL::Digest.new("SHA256").update(s).hexfinal
        end

        private Log = ::Log.for("dirless.ops.cert")
      end
    end
  end
end
