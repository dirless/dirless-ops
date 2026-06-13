require "option_parser"
require "../config"
require "../client"
require "../table"

module Dirless
  module Ops
    module CLI
      module Commands
        module Customers
          VALID_PLANS = {"free", "growth", "scale"}

          # Characters used for auto-generated passwords: mixed case + digits.
          # No special characters to avoid copy-paste / terminal escaping issues.
          PASSWORD_CHARS = (('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a)
          PASSWORD_LEN   = 20

          def self.needs_tunnel?(args : Array(String)) : Bool
            return false if args.empty?
            sub = args.first
            return false if {"help", "--help", "-h"}.includes?(sub)
            return false if {"show", "delete"}.includes?(sub) && args.size == 1
            true
          end

          def self.run(args : Array(String), config : Config) : Nil
            if args.empty?
              puts usage
              exit 0
            end

            subcommand = args.shift
            client = Client.new(config)

            case subcommand
            when "list"   then list(client)
            when "create" then create(args, client, config)
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
              ["NAME", "COMPANY", "EMAIL", "PLAN", "PROVISIONED", "VERIFIED"],
              customers.map { |customer|
                [
                  customer["name"].as_s,
                  customer["company"].as_s? || "-",
                  customer["email"].as_s? || "-",
                  customer["plan"].as_s? || "free",
                  customer["provisioned"].as_bool? ? "yes" : "no",
                  customer["email_verified"].as_bool? ? "yes" : "no",
                ]
              }
            )
          end

          # ameba:disable Metrics/CyclomaticComplexity
          private def self.create(args : Array(String), client : Client, config : Config) : Nil
            email = nil
            password = nil
            first_name = nil
            last_name = nil
            company = nil
            country = "US"
            plan = "free"
            verified = false
            random_aws_account_id = false

            OptionParser.parse(args) do |opt|
              opt.banner = "Usage: dirless-ops-cli customers create [options]"
              opt.on("--email EMAIL", "Customer email address") { |v| email = v }
              opt.on("--password PASSWORD", "Password override (auto-generated if omitted)") { |v| password = v }
              opt.on("--first-name NAME", "First name") { |v| first_name = v }
              opt.on("--last-name NAME", "Last name") { |v| last_name = v }
              opt.on("--company COMPANY", "Company / organisation name") { |v| company = v }
              opt.on("--country CODE", "ISO 3166-1 alpha-2 country code (default: US)") { |v| country = v.upcase }
              opt.on("--plan PLAN", "Plan: free, growth, scale (default: free)") { |v| plan = v.downcase }
              opt.on("--verified", "Mark email as already verified (skips verification email)") { verified = true }
              opt.on("--random-aws-account-id", "Generate a random 12-digit AWS account ID (useful for staging)") { random_aws_account_id = true }
              opt.on("-h", "--help", "Show help") { puts opt; exit 0 }
              opt.invalid_option { |flag| STDERR.puts "Unknown option: #{flag}"; STDERR.puts opt; exit 1 }
            end

            unless VALID_PLANS.includes?(plan)
              STDERR.puts "Error: invalid plan '#{plan}'. Valid plans: #{VALID_PLANS.join(", ")}"
              exit 1
            end

            env_label = config.env_name.empty? ? "" : " [#{config.env_name}]"
            puts "Creating customer on #{config.url}#{env_label}"
            puts ""

            # Collect any fields not supplied via flags interactively.
            email_s = email || prompt("Email: ")
            first_name_s = first_name || prompt("First name: ")
            last_name_s = last_name || prompt("Last name: ")
            company_s = company || prompt("Company: ")

            # Auto-generate a password unless one was explicitly provided.
            generated_password = password.nil?
            password_s = password || generate_password

            body = {
              "email"          => email_s,
              "password"       => password_s,
              "first_name"     => first_name_s,
              "last_name"      => last_name_s,
              "company"        => company_s,
              "country"        => country,
              "email_verified" => verified.to_s,
            }

            print "Creating customer for #{email_s}... "
            STDOUT.flush
            customer = client.post("/v1/portal/register", body)
            puts "done."

            aws_account_id = nil
            if random_aws_account_id
              aws_account_id = "%012d" % Random::Secure.rand(1_000_000_000_000_i64)
              client.patch("/v1/customers/#{customer["name"].as_s}", {"aws_account_id" => aws_account_id})
            end

            puts ""
            puts "  Email:         #{customer["email"]}"
            puts "  Name:          #{customer["name"]}"
            puts "  Company:       #{customer["company"].as_s? || "-"}"
            puts "  Plan:          #{customer["plan"].as_s? || "free"}"
            puts "  Provisioned:   #{customer["provisioned"]}"
            puts "  Created:       #{customer["created_at"].as_s? || "-"}"
            puts "  AWS Account ID: #{aws_account_id || "-"}"

            if generated_password
              puts ""
              puts "  Password:      #{password_s}"
              puts "  ⚠  Share this securely — it won't be shown again."
            end

            puts ""
            puts "Welcome and verification emails sent to #{email_s}."
            puts "Provisioning will start automatically within ~30 seconds."

            if {"growth", "scale"}.includes?(plan)
              puts ""
              puts "Note: --plan #{plan} was specified but the portal register endpoint"
              puts "always creates accounts on the Free plan. Direct the customer to"
              puts "portal.dirless.com to complete payment and activate the #{plan} plan."
            end
          end

          private def self.show(args : Array(String), client : Client) : Nil
            name = args.shift? || begin
              STDERR.puts "Usage: dirless-ops-cli customers show <name>"
              exit 1
            end

            c = client.get("/v1/customers/#{name}")
            puts "Name:           #{c["name"]}"
            puts "Company:        #{c["company"].as_s? || "-"}"
            puts "Email:          #{c["email"].as_s? || "-"}"
            puts "Plan:           #{c["plan"].as_s? || "free"}"
            puts "Provisioned:    #{c["provisioned"].as_bool? ? "yes" : "no"}"
            puts "Email Verified: #{c["email_verified"].as_bool? ? "yes" : "no"}"
            puts "Port:           #{c["port"]}"
            puts "HMAC Secret:    #{c["hmac_secret"]}"
            puts "AWS Account ID: #{c["aws_account_id"].as_s? || "-"}"
            puts "Notes:          #{c["notes"].as_s? || "-"}"
            puts "Created:        #{c["created_at"]}"
          end

          private def self.update(args : Array(String), client : Client) : Nil
            name = args.shift? || begin
              STDERR.puts "Usage: dirless-ops-cli customers update <name> [options]"
              exit 1
            end

            body = {} of String => String

            OptionParser.parse(args) do |opt|
              opt.banner = "Usage: dirless-ops-cli customers update <name> [options]"
              opt.on("--hmac-secret SECRET", "New HMAC secret") { |v| body["hmac_secret"] = v }
              opt.on("--company COMPANY", "New company name") { |v| body["company"] = v }
              opt.on("--aws-account-id ID", "New AWS account ID") { |v| body["aws_account_id"] = v }
              opt.on("--notes NOTES", "New notes") { |v| body["notes"] = v }
              opt.on("-h", "--help", "Show help") { puts opt; exit 0 }
              opt.invalid_option { |flag| STDERR.puts "Unknown option: #{flag}"; STDERR.puts opt; exit 1 }
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
              STDERR.puts "Usage: dirless-ops-cli customers delete <name>"
              exit 1
            end

            client.delete("/v1/customers/#{name}")
            puts "Deleted: #{name}"
          end

          # Generates a cryptographically secure random password.
          private def self.generate_password : String
            Array.new(PASSWORD_LEN) { PASSWORD_CHARS.sample(Random::Secure) }.join
          end

          # Read a required single-line value from stdin.
          private def self.prompt(label : String) : String
            print label
            STDOUT.flush
            value = STDIN.gets.to_s.strip
            if value.empty?
              STDERR.puts "Error: #{label.strip.chomp(':').downcase} is required"
              exit 1
            end
            value
          end

          private def self.usage : String
            <<-USAGE
            Usage: dirless-ops-cli customers <subcommand> [options]

            Subcommands:
              list      List all customers
              create    Create a new customer (full registration + provision flow)
              show      <name>
              update    <name> [--company] [--hmac-secret] [--aws-account-id] [--notes]
              delete    <name>

            Examples:
              dirless-ops-cli customers list
              dirless-ops-cli customers create
              dirless-ops-cli customers create --email alice@corp.com --first-name Alice \\
                --last-name Smith --company Acme --country GB
              dirless-ops-cli customers create --email test@staging.com --random-aws-account-id
              dirless-ops-cli --env prod customers create --email alice@corp.com
              dirless-ops-cli customers show ewmilnqiuhxu-5000

            Run 'dirless-ops-cli customers create --help' for all flags.
            USAGE
          end
        end
      end
    end
  end
end
