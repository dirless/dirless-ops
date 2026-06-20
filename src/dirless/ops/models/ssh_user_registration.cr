require "granite"

module Dirless
  module Ops
    class SshUserRegistration < Granite::Base
      connection sqlite
      table ssh_user_registrations

      column id : Int64, primary: true
      column customer_name : String
      column username : String
      column email : String
      column age_public_key : String
      column ssh_public_key : String

      timestamps
    end
  end
end
