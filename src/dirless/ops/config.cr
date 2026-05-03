require "toml"

module Dirless
  module Ops
    class Config
      getter host : String
      getter port : Int32
      getter api_key : String
      getter database_path : String
      getter polling_interval_seconds : Int32
      getter ansible_inventory : String?
      getter ansible_playbook : String?
      getter mail_spool_dir : String
      getter ops_alert_email : String?

      def initialize(path : String)
        raw = File.read(path)
        toml = TOML.parse(raw)

        @host = toml["server"]["host"].as_s
        @port = toml["server"]["port"].as_i
        @api_key = toml["api"]["key"].as_s
        @database_path = toml["database"]["path"].as_s
        @polling_interval_seconds = toml["polling"]["interval_seconds"].as_i

        if deployer = toml["deployer"]?
          @ansible_inventory = deployer["ansible_inventory"]?.try(&.as_s)
          @ansible_playbook = deployer["ansible_playbook"]?.try(&.as_s)
        end

        @mail_spool_dir = toml["notifications"]?.try(&.["mail_spool_dir"]?.try(&.as_s)) ||
                          "/var/spool/dirless-ops/outbox"
        @ops_alert_email = toml["notifications"]?.try(&.["ops_alert_email"]?.try(&.as_s))
      end

      def self.load(path : String) : Config
        new(path)
      end
    end
  end
end
