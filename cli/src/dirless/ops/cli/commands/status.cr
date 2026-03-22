require "../config"
require "../client"
require "../table"

module Dirless
  module Ops
    module CLI
      module Commands
        module Status
          def self.run(args : Array(String), config : Config) : Nil
            client = Client.new(config)
            customers = client.get("/v1/status").as_a

            if customers.empty?
              puts "No customers configured."
              return
            end

            customers.each do |customer|
              label = customer["label"].as_s? || customer["name"].as_s
              puts "\n#{label} (#{customer["name"]})"
              puts "-" * 60

              nodes = customer["nodes"].as_a
              if nodes.empty?
                puts "  No nodes configured."
                next
              end

              Table.print(
                ["NODE", "REGION", "STATUS", "HTTP", "MS", "CHECKED AT"],
                nodes.map { |n|
                  status = n["status"].as_s
                  [
                    n["node_name"].as_s,
                    n["region"].as_s,
                    CLI.colorize_status(status),
                    n["http_status"].as_i?.try(&.to_s) || "-",
                    n["response_time_ms"].as_i?.try(&.to_s) || "-",
                    n["checked_at"].as_s? || "never",
                  ]
                }
              )
            end
            puts ""
          end
        end
      end
    end
  end
end
