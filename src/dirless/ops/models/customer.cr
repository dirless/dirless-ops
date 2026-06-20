require "granite"
require "crypto/bcrypt/password"

module Dirless
  module Ops
    class Customer < Granite::Base
      connection sqlite
      table customers

      column id : Int64, primary: true
      column name : String
      column label : String? # legacy; superseded by company
      column hmac_secret : String
      column aws_account_id : String?
      column notes : String?
      column tenant_id : String?

      # Account fields (merged from customer_accounts table)
      column email : String?
      column password_hash : String?
      column first_name : String?
      column last_name : String?
      column company : String?
      column country : String?
      column provisioned : Bool?
      column email_verified : Bool?
      column email_verify_token : String?
      column stripe_customer_id : String?
      column beta_customer : Bool?
      column plan : String?
      column server_limit : Int64?
      column ca_private_key : String?
      column ca_public_key : String?
      column cert_ttl_seconds : Int64?

      timestamps

      def self.limit_for_plan(plan : String?) : Int64
        case plan
        when "growth" then 50_i64
        when "scale"  then 200_i64
        else               10_i64
        end
      end

      def port : Int32
        (name || "").split("-").last.to_i
      rescue ArgumentError
        0
      end

      def self.hash_password(password : String) : String
        Crypto::Bcrypt::Password.create(password, cost: 12).to_s
      end

      def verify_password(password : String) : Bool
        Crypto::Bcrypt::Password.new(password_hash || "").verify(password)
      rescue
        false
      end

      def to_response
        {
          "id"             => id,
          "name"           => name,
          "hmac_secret"    => hmac_secret,
          "aws_account_id" => aws_account_id,
          "notes"          => notes,
          "tenant_id"      => tenant_id,
          "port"           => port,
          "email"          => email,
          "first_name"     => first_name,
          "last_name"      => last_name,
          "company"        => company,
          "country"        => country,
          "provisioned"    => provisioned,
          "email_verified" => email_verified,
          "plan"              => plan || "free",
          "server_limit"      => server_limit || Customer.limit_for_plan(plan),
          "ca_public_key"     => ca_public_key,
          "cert_ttl_seconds"  => cert_ttl_seconds,
          "created_at"     => created_at.try(&.to_rfc3339),
          "updated_at"     => updated_at.try(&.to_rfc3339),
        }
      end
    end
  end
end
