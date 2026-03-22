require "option_parser"
require "../config"
require "../client"
require "../table"

module Dirless
  module Ops
    module CLI
      module Commands
        module Customers
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
            customers = client.get("/v1/customers").as_a
            if customers.empty?
              puts "No customers."
              return
            end
            Table.print(
              ["NAME", "LABEL", "PORT", "AWS ACCOUNT"],
              customers.map { |c|
                [
                  c["name"].as_s,
                  c["label"].as_s? || "-",
                  c["port"].as_i.to_s,
                  c["aws_account_id"].as_s? || "-",
                ]
              }
            )
          end

          private def self.add(args : Array(String), client : Client) : Nil
            name = nil
            hmac_secret = nil
            label = nil
            aws_account_id = nil
            notes = nil

            OptionParser.parse(args) do |p|
              p.banner = "Usage: dirless-ops customers add [options]"
              p.on("--name NAME", "Customer name (e.g. ewmilnqiuhxu-5000)") { |v| name = v }
              p.on("--hmac-secret SECRET", "HMAC enrollment secret") { |v| hmac_secret = v }
              p.on("--label LABEL", "Human-readable label") { |v| label = v }
              p.on("--aws-account-id ID", "AWS account ID") { |v| aws_account_id = v }
              p.on("--notes NOTES", "Notes") { |v| notes = v }
              p.on("-h", "--help", "Show help") { puts p; exit 0 }
            end

            unless name && hmac_secret
              STDERR.puts "Error: --name and --hmac-secret are required"
              exit 1
            end

            body = {"name" => name, "hmac_secret" => hmac_secret} of String => String?
            body["label"] = label if label
            body["aws_account_id"] = aws_account_id if aws_account_id
            body["notes"] = notes if notes

            customer = client.post("/v1/customers/", body)
            puts "Created: #{customer["name"]}"
          end

          private def self.show(args : Array(String), client : Client) : Nil
            name = args.shift? || begin
              STDERR.puts "Usage: dirless-ops customers show <name>"
              exit 1
            end

            c = client.get("/v1/customers/#{name}")
            puts "Name:           #{c["name"]}"
            puts "Label:          #{c["label"].as_s? || "-"}"
            puts "Port:           #{c["port"]}"
            puts "HMAC Secret:    #{c["hmac_secret"]}"
            puts "AWS Account ID: #{c["aws_account_id"].as_s? || "-"}"
            puts "Notes:          #{c["notes"].as_s? || "-"}"
            puts "Created:        #{c["created_at"]}"
          end

          private def self.update(args : Array(String), client : Client) : Nil
            name = args.shift? || begin
              STDERR.puts "Usage: dirless-ops customers update <name> [options]"
              exit 1
            end

            body = {} of String => String

            OptionParser.parse(args) do |p|
              p.banner = "Usage: dirless-ops customers update <name> [options]"
              p.on("--hmac-secret SECRET", "New HMAC secret") { |v| body["hmac_secret"] = v }
              p.on("--label LABEL", "New label") { |v| body["label"] = v }
              p.on("--aws-account-id ID", "New AWS account ID") { |v| body["aws_account_id"] = v }
              p.on("--notes NOTES", "New notes") { |v| body["notes"] = v }
              p.on("-h", "--help", "Show help") { puts p; exit 0 }
            end

            if body.empty?
              STDERR.puts "Error: provide at least one field to update"
              exit 1
            end

            client.patch("/v1/customers/#{name}", body)
            puts "Updated: #{name}"
          end

          private def self.delete(args : Array(String), client : Client) : Nil
            name = args.shift? || begin
              STDERR.puts "Usage: dirless-ops customers delete <name>"
              exit 1
            end

            client.delete("/v1/customers/#{name}")
            puts "Deleted: #{name}"
          end

          private def self.usage : String
            <<-USAGE
            Usage: dirless-ops customers <subcommand> [options]

            Subcommands:
              list                      List all customers
              add    --name --hmac-secret [--label] [--aws-account-id] [--notes]
              show   <name>
              update <name> [--hmac-secret] [--label] [--aws-account-id] [--notes]
              delete <name>
            USAGE
          end
        end
      end
    end
  end
end
