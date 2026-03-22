require "option_parser"
require "./dirless/ops/cli/config"
require "./dirless/ops/cli/client"
require "./dirless/ops/cli/table"
require "./dirless/ops/cli/commands/customers"
require "./dirless/ops/cli/commands/nodes"
require "./dirless/ops/cli/commands/status"

module Dirless
  module Ops
    module CLI
      VERSION = "0.1.0"

      def self.run(args : Array(String)) : Nil
        if args.empty?
          puts usage
          exit 0
        end

        subcommand = args.shift

        case subcommand
        when "customers"
          config = Config.from_env
          Commands::Customers.run(args, config)
        when "nodes"
          config = Config.from_env
          Commands::Nodes.run(args, config)
        when "status"
          config = Config.from_env
          Commands::Status.run(args, config)
        when "version", "--version", "-v"
          puts VERSION
        when "help", "--help", "-h"
          puts usage
        else
          STDERR.puts "Unknown command: #{subcommand}"
          STDERR.puts usage
          exit 1
        end
      end

      private def self.usage : String
        <<-USAGE
        dirless-ops #{VERSION}

        Usage:
          dirless-ops <command> [subcommand] [options]

        Commands:
          customers   Manage customers
          nodes       Manage backend nodes
          status      Show health status across all nodes
          version     Print version

        Environment:
          DIRLESS_OPS_URL   Daemon URL (default: http://localhost:5000)
          DIRLESS_OPS_KEY   API key (required)

        Run 'dirless-ops <command>' for subcommand help.
        USAGE
      end
    end
  end
end

Dirless::Ops::CLI.run(ARGV)
