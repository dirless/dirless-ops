require "granite"


module Dirless
  module Ops
    class Customer < Granite::Base
      connection sqlite
      table customers

      column id : Int64, primary: true
      column name : String
      column label : String?
      column hmac_secret : String
      column aws_account_id : String?
      column notes : String?
      timestamps

      def port : Int32
        (name || "").split("-").last.to_i
      rescue ArgumentError
        0
      end

      def to_response
        {
          "id"             => id,
          "name"           => name,
          "label"          => label,
          "hmac_secret"    => hmac_secret,
          "aws_account_id" => aws_account_id,
          "notes"          => notes,
          "port"           => port,
          "created_at"     => created_at.try(&.to_rfc3339),
          "updated_at"     => updated_at.try(&.to_rfc3339),
        }
      end
    end
  end
end
