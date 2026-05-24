require "granite"

require "crypto/bcrypt/password"

module Dirless
  module Ops
    class CustomerAccount < Granite::Base
      connection sqlite
      table customer_accounts

      column id : Int64, primary: true
      column email : String
      column password_hash : String
      column customer_name : String
      column first_name : String?
      column last_name : String?
      column company : String?
      column country : String?
      column provisioned : Bool
      column email_verified : Bool
      column email_verify_token : String?
      column stripe_customer_id : String?
      column beta_customer : Bool
      column plan : String?
      timestamps

      def self.hash_password(password : String) : String
        Crypto::Bcrypt::Password.create(password, cost: 12).to_s
      end

      def verify_password(password : String) : Bool
        Crypto::Bcrypt::Password.new(password_hash.not_nil!).verify(password)
      rescue
        false
      end

      def to_response
        {
          "id"            => id,
          "email"         => email,
          "customer_name" => customer_name,
          "first_name"    => first_name,
          "last_name"     => last_name,
          "company"       => company,
          "country"       => country,
          "provisioned"    => provisioned,
          "email_verified" => email_verified,
          "plan"           => (plan || "beta"),
          "created_at"     => created_at.try(&.to_rfc3339),
        }
      end
    end
  end
end
