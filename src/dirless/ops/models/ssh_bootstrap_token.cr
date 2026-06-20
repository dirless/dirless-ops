require "granite"

module Dirless
  module Ops
    class SshBootstrapToken < Granite::Base
      connection sqlite
      table ssh_bootstrap_tokens

      column id : Int64, primary: true
      column token : String
      column customer_name : String
      column username : String
      column email : String
      column age_public_key : String
      column ssh_public_key : String
      column used : Bool
      column expires_at : Time?

      timestamps

      def expired? : Bool
        if exp = expires_at
          Time.utc > exp
        else
          true
        end
      end
    end
  end
end
