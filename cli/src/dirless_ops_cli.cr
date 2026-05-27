require "option_parser"
require "./dirless/ops/cli/config"
require "./dirless/ops/cli/tunnel"
require "./dirless/ops/cli/client"
require "./dirless/ops/cli/table"
require "./dirless/ops/cli/commands/customers"
require "./dirless/ops/cli/commands/nodes"
require "./dirless/ops/cli/commands/status"
require "./dirless/ops/cli/commands/provision_jobs"

module Dirless
  module Ops
    module CLI
      VERSION = {{ `shards version #{__DIR__}/..`.chomp.stringify }}

      # ameba:disable Metrics/CyclomaticComplexity
      def self.run(args : Array(String)) : Nil
        env_name : String? = nil
        ssh_key : String? = nil
        ssh_user : String? = nil

        # Consume global flags that appear before the subcommand.
        while first = args.first?
          case first
          when "--env"
            args.shift
            env_name = args.shift? || begin
              STDERR.puts "Error: --env requires an environment name (prod or staging)"
              exit 1
            end
          when "--private-ssh-key"
            args.shift
            ssh_key = args.shift? || begin
              STDERR.puts "Error: --private-ssh-key requires a path to a private key file"
              exit 1
            end
          when "--ssh-user"
            args.shift
            ssh_user = args.shift? || begin
              STDERR.puts "Error: --ssh-user requires a username"
              exit 1
            end
          when "--version", "-v"
            puts VERSION
            return
          when "--help", "-h"
            puts usage
            return
          else
            break
          end
        end

        if args.empty?
          puts usage
          exit 0
        end

        subcommand = args.shift

        # For help / no-subcommand cases, skip config + tunnel entirely.
        help_only = args.empty? || args.any? { |arg| arg == "--help" || arg == "-h" }

        # If --env wasn't given and we're about to make a real API call,
        # offer an fzf picker. Falls back gracefully if fzf isn't installed.
        if env_name.nil? && !help_only && !{"version", "help"}.includes?(subcommand)
          env_name = pick_env_fzf
        end

        case subcommand
        when "customers", "nodes", "status", "provision-jobs"
          needs_tunnel = case subcommand
                         when "customers"      then Commands::Customers.needs_tunnel?(args)
                         when "nodes"          then Commands::Nodes.needs_tunnel?(args)
                         when "provision-jobs" then Commands::ProvisionJobs.needs_tunnel?(args)
                         else                       true # status always needs a connection
                         end

          if needs_tunnel
            config = Config.from_env(env_name, ssh_key, ssh_user)
            Tunnel.ensure_ready(config)
          else
            config = Config.new("", "", "")
          end

          case subcommand
          when "customers"      then Commands::Customers.run(args, config)
          when "nodes"          then Commands::Nodes.run(args, config)
          when "status"         then Commands::Status.run(args, config)
          when "provision-jobs" then Commands::ProvisionJobs.run(args, config)
          end
        when "version"
          puts VERSION
        when "help"
          puts usage
        else
          STDERR.puts "Unknown command: #{subcommand}"
          STDERR.puts ""
          STDERR.puts usage
          exit 1
        end
      end

      # Prompt the user to pick an environment using fzf.
      # Returns the selected environment name, or nil if fzf isn't installed
      # or the user cancelled (Escape / Ctrl-C).
      private def self.pick_env_fzf : String?
        input = IO::Memory.new(Tunnel::HOSTS.keys.join("\n") + "\n")
        output = IO::Memory.new

        Process.run(
          "fzf",
          ["--prompt=Environment > ", "--height=~5", "--border", "--no-sort"],
          input: input,
          output: output,
          error: Process::Redirect::Close
        )

        selection = output.to_s.strip
        selection.empty? ? nil : selection
      rescue
        # fzf not installed — proceed without an env (local mode).
        nil
      end

      private def self.usage : String
        <<-USAGE
        dirless-ops-cli #{VERSION}

        Usage:
          dirless-ops-cli [--env ENV] [--private-ssh-key PATH] [--ssh-user USER] <command> [subcommand] [options]

        Global flags:
          --env ENV              Environment: prod or staging.
                                 Opens an SSH tunnel automatically if port 5000 is
                                 not already open locally.
                                   prod    → admin.dirless.com
                                   staging → staging-admin.dirless.com
                                 Omit to be prompted with fzf (if installed).
          --private-ssh-key PATH Path to SSH private key (default: ~/.ssh/id_ed25519_racknerd_floridian_goat)
          --ssh-user USER        SSH username (default: root)

        Commands:
          customers       Manage customers (registration, CRUD)
          nodes           Manage backend nodes
          provision-jobs  List and manage provision jobs
          status          Show health status across all nodes
          version         Print version

        API key:
          Read automatically — no env vars needed.
          With --env: fetched via SSH from the remote server config.
          Without --env: read directly from /etc/dirless-ops/dirless-ops.toml.
          Override: DIRLESS_OPS_KEY_PROD / DIRLESS_OPS_KEY_STAGING / DIRLESS_OPS_KEY

        Examples:
          dirless-ops-cli --env prod customers create --email alice@corp.com
          dirless-ops-cli --env staging customers list
          dirless-ops-cli customers create    # fzf picker appears if --env omitted
          dirless-ops-cli status             # on the ops machine itself — no tunnel needed

        Run 'dirless-ops-cli <command>' for subcommand help.
        USAGE
      end
    end
  end
end

Dirless::Ops::CLI.run(ARGV)
