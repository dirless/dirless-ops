require "option_parser"
require "../config"
require "../client"
require "../table"

module Dirless
  module Ops
    module CLI
      module Commands
        module ProvisionJobs
          # Returns false when the args clearly don't need a server connection
          # (help, missing required argument, etc.) so the main CLI can skip
          # opening the SSH tunnel.
          def self.needs_tunnel?(args : Array(String)) : Bool
            return false if args.empty?
            sub = args.first
            return false if {"help", "--help", "-h"}.includes?(sub)
            return false if {"show", "reset"}.includes?(sub) && args.size == 1
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
            when "list"  then list(args, client)
            when "show"  then show(args, client)
            when "reset" then reset(args, client)
            when "help", "--help", "-h"
              puts usage
            else
              STDERR.puts "Unknown subcommand: #{subcommand}"
              STDERR.puts usage
              exit 1
            end
          end

          private def self.list(args : Array(String), client : Client) : Nil
            status = nil

            OptionParser.parse(args) do |opt|
              opt.banner = "Usage: dirless-ops-cli provision-jobs list [--status STATUS]"
              opt.on("--status STATUS", "Filter by status: pending, in_progress, completed, failed") { |v| status = v }
              opt.on("-h", "--help", "Show help") { puts opt; exit 0 }
              opt.invalid_option { |flag| STDERR.puts "Unknown option: #{flag}"; STDERR.puts opt; exit 1 }
            end

            url = status ? "/v1/provision-jobs?status=#{status}" : "/v1/provision-jobs"
            jobs = client.get(url).as_a

            if jobs.empty?
              puts "No provision jobs."
              return
            end

            Table.print(
              ["ID", "CUSTOMER", "STATUS", "RESETS", "ERROR", "CREATED"],
              jobs.map { |j|
                error = j["error"].as_s? || ""
                error = error[0, 40] + "…" if error.size > 40
                resets = (j["reset_count"]?.try(&.as_i?) || 0).to_s
                [
                  j["id"].to_s,
                  j["customer_name"].as_s,
                  j["status"].as_s,
                  resets,
                  error,
                  j["created_at"].as_s? || "-",
                ]
              }
            )
          end

          private def self.show(args : Array(String), client : Client) : Nil
            id = args.shift? || begin
              STDERR.puts "Usage: dirless-ops-cli provision-jobs show <id>"
              exit 1
            end

            j = client.get("/v1/provision-jobs/#{id}")
            puts "ID:           #{j["id"]}"
            puts "Customer:     #{j["customer_name"]}"
            puts "Status:       #{j["status"]}"
            puts "Resets:       #{j["reset_count"]?.try(&.as_i?) || 0}"
            puts "Error:        #{j["error"].as_s? || "-"}"
            puts "Started:      #{j["started_at"].as_s? || "-"}"
            puts "Completed:    #{j["completed_at"].as_s? || "-"}"
            puts "Created:      #{j["created_at"].as_s? || "-"}"
          end

          private def self.reset(args : Array(String), client : Client) : Nil
            id = args.shift? || begin
              STDERR.puts "Usage: dirless-ops-cli provision-jobs reset <id>"
              exit 1
            end

            client.patch("/v1/provision-jobs/#{id}", {"status" => "pending"})
            puts "Job #{id} reset to pending."
          end

          private def self.usage : String
            <<-USAGE
            Usage: dirless-ops-cli provision-jobs <subcommand> [options]

            Subcommands:
              list   [--status pending|in_progress|completed|failed]
              show   <id>
              reset  <id>    Reset a failed/stuck job back to pending
            USAGE
          end
        end
      end
    end
  end
end
