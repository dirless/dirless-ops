require "granite"

module Dirless
  module Ops
    class SshChallenge < Granite::Base
      connection sqlite
      table ssh_challenges

      column id : Int64, primary: true
      column customer_name : String
      column username : String
      column nonce_hash : String
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
