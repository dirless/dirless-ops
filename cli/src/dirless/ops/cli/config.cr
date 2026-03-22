module Dirless
  module Ops
    module CLI
      class Config
        getter url : String
        getter api_key : String

        def initialize(@url : String, @api_key : String)
        end

        def self.from_env : Config
          url = ENV.fetch("DIRLESS_OPS_URL", "http://localhost:5000")
          key = ENV["DIRLESS_OPS_KEY"]? || begin
            STDERR.puts "Error: DIRLESS_OPS_KEY environment variable is required"
            exit 1
          end
          new(url, key)
        end
      end
    end
  end
end
