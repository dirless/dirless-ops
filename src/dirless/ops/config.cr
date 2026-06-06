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
      getter ansible_ops_url : String?
      getter deprovision_playbook : String?
      getter mail_spool_dir : String
      getter ops_alert_email : String?
      getter portal_url : String
      getter backend_domain : String
      getter deprovision_spool_dir : String
      getter stripe_secret_key : String?
      getter stripe_publishable_key : String?
      getter beta_mode : Bool
      getter stripe_prices : Hash(String, String)

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
          @ansible_ops_url = deployer["ansible_ops_url"]?.try(&.as_s)
          @deprovision_playbook = deployer["deprovision_playbook"]?.try(&.as_s)
        end

        @mail_spool_dir = toml["notifications"]?.try(&.["mail_spool_dir"]?.try(&.as_s)) ||
                          "/var/spool/dirless-ops/outbox"
        @ops_alert_email = toml["notifications"]?.try(&.["ops_alert_email"]?.try(&.as_s))
        @portal_url = toml["notifications"]?.try(&.["portal_url"]?.try(&.as_s)) ||
                      "https://portal.dirless.com"
        @backend_domain = toml["backend"]?.try(&.["domain"]?.try(&.as_s)) || "dirless.com"
        @deprovision_spool_dir = toml["deployer"]?.try(&.["deprovision_spool_dir"]?.try(&.as_s)) ||
                                 "/var/spool/dirless-ops/deprovision"
        @stripe_secret_key = toml["stripe"]?.try(&.["secret_key"]?.try(&.as_s))
        @stripe_publishable_key = toml["stripe"]?.try(&.["publishable_key"]?.try(&.as_s))
        @beta_mode = toml["stripe"]?.try(&.["beta_mode"]?.try(&.as_bool)) || true
        @stripe_prices = {} of String => String
        if prices = toml["stripe_prices"]?
          prices.as_h.each do |k, v|
            @stripe_prices[k] = v.as_s
          end
        end
      end

      def self.load(path : String) : Config
        new(path)
      end
    end
  end
end
