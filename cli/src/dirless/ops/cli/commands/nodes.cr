require "option_parser"
require "../config"
require "../client"
require "../table"

module Dirless
  module Ops
    module CLI
      module Commands
        module Nodes
          def self.run(args : Array(String), config : Config) : Nil
            if args.empty?
              STDERR.puts usage
              exit 1
            end

            subcommand = args.shift
            client = Client.new(config)

            case subcommand
            when "list"   then list(client)
            when "add"    then add(args, client)
            when "show"   then show(args, client)
            when "update" then update(args, client)
            when "delete" then delete(args, client)
            when "help", "--help", "-h"
              puts usage
            else
              STDERR.puts "Unknown subcommand: #{subcommand}"
              STDERR.puts usage
              exit 1
            end
          end

          private def self.list(client : Client) : Nil
            nodes = client.get("/v1/nodes").as_a
            if nodes.empty?
              puts "No nodes."
              return
            end
            Table.print(
              ["NAME", "IP", "REGION", "PROVIDER", "PRIMARY"],
              nodes.map { |n|
                [
                  n["name"].as_s,
                  n["ip"].as_s,
                  n["region"].as_s,
                  n["provider"].as_s,
                  n["is_primary"].as_bool ? "yes" : "no",
                ]
              }
            )
          end

          private def self.add(args : Array(String), client : Client) : Nil
            name = nil
            ip = nil
            region = nil
            provider = "atlanticnet"
            is_primary = false

            OptionParser.parse(args) do |p|
              p.banner = "Usage: dirless-ops nodes add [options]"
              p.on("--name NAME", "Node name (e.g. node-0)") { |v| name = v }
              p.on("--ip IP", "Node IP address") { |v| ip = v }
              p.on("--region REGION", "Region (e.g. USEAST2)") { |v| region = v }
              p.on("--provider PROVIDER", "Provider (default: atlanticnet)") { |v| provider = v }
              p.on("--primary", "Mark as primary node") { is_primary = true }
              p.on("-h", "--help", "Show help") { puts p; exit 0 }
            end

            unless name && ip && region
              STDERR.puts "Error: --name, --ip, and --region are required"
              exit 1
            end

            body = {
              "name"       => name,
              "ip"         => ip,
              "region"     => region,
              "provider"   => provider,
              "is_primary" => is_primary.to_s,
            }

            node = client.post("/v1/nodes/", body)
            puts "Created: #{node["name"]}"
          end

          private def self.show(args : Array(String), client : Client) : Nil
            name = args.shift? || begin
              STDERR.puts "Usage: dirless-ops nodes show <name>"
              exit 1
            end

            n = client.get("/v1/nodes/#{name}")
            puts "Name:     #{n["name"]}"
            puts "IP:       #{n["ip"]}"
            puts "Region:   #{n["region"]}"
            puts "Provider: #{n["provider"]}"
            puts "Primary:  #{n["is_primary"].as_bool ? "yes" : "no"}"
            puts "Created:  #{n["created_at"]}"
          end

          private def self.update(args : Array(String), client : Client) : Nil
            name = args.shift? || begin
              STDERR.puts "Usage: dirless-ops nodes update <name> [options]"
              exit 1
            end

            body = {} of String => String

            OptionParser.parse(args) do |p|
              p.banner = "Usage: dirless-ops nodes update <name> [options]"
              p.on("--ip IP", "New IP address") { |v| body["ip"] = v }
              p.on("--region REGION", "New region") { |v| body["region"] = v }
              p.on("--provider PROVIDER", "New provider") { |v| body["provider"] = v }
              p.on("--primary", "Mark as primary") { body["is_primary"] = "true" }
              p.on("--no-primary", "Unmark as primary") { body["is_primary"] = "false" }
              p.on("-h", "--help", "Show help") { puts p; exit 0 }
            end

            if body.empty?
              STDERR.puts "Error: provide at least one field to update"
              exit 1
            end

            client.patch("/v1/nodes/#{name}", body)
            puts "Updated: #{name}"
          end

          private def self.delete(args : Array(String), client : Client) : Nil
            name = args.shift? || begin
              STDERR.puts "Usage: dirless-ops nodes delete <name>"
              exit 1
            end

            client.delete("/v1/nodes/#{name}")
            puts "Deleted: #{name}"
          end

          private def self.usage : String
            <<-USAGE
            Usage: dirless-ops nodes <subcommand> [options]

            Subcommands:
              list                               List all nodes
              add    --name --ip --region [--provider] [--primary]
              show   <name>
              update <name> [--ip] [--region] [--provider] [--primary|--no-primary]
              delete <name>
            USAGE
          end
        end
      end
    end
  end
end
