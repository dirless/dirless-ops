require "toml"

module Dirless
  module Ops
    class Config
      getter host : String
      getter port : Int32
      getter api_key : String
      getter database_path : String
      getter polling_interval_seconds : Int32

      def initialize(path : String)
        raw = File.read(path)
        toml = TOML.parse(raw)

        @host = toml["server"]["host"].as_s
        @port = toml["server"]["port"].as_i
        @api_key = toml["api"]["key"].as_s
        @database_path = toml["database"]["path"].as_s
        @polling_interval_seconds = toml["polling"]["interval_seconds"].as_i
      end

      def self.load(path : String) : Config
        new(path)
      end
    end
  end
end
