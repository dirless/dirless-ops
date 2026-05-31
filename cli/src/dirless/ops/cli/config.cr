module Dirless
  module Ops
    module CLI
      class Config
        DEFAULT_SSH_KEY  = "#{Path.home}/.ssh/id_ed25519_racknerd_floridian_goat"
        DEFAULT_SSH_USER = "root"
        REMOTE_CONFIG    = "/etc/dirless-ops/dirless-ops.toml"

        getter url : String
        getter api_key : String
        getter env_name : String
        getter remote_host : String? # nil when running directly on the ops machine
        getter ssh_key_path : String
        getter ssh_user : String
        getter local_port : Int32

        def initialize(
          @url : String,
          @api_key : String,
          @env_name : String = "",
          @remote_host : String? = nil,
          @ssh_key_path : String = DEFAULT_SSH_KEY,
          @ssh_user : String = DEFAULT_SSH_USER,
          @local_port : Int32 = Tunnel::REMOTE_PORT,
        )
        end

        # Build config from environment + CLI flags.
        #
        # With --env NAME (e.g. "prod", "staging"):
        #   - remote host looked up from the fixed HOSTS table in Tunnel
        #   - local tunnel port: 15000 for prod, 15001 for staging (avoids clashing with dev)
        #   - SSH key: --private-ssh-key flag > DIRLESS_OPS_SSH_KEY env > default key
        #   - SSH user: --ssh-user flag > "root"
        #   - API key: DIRLESS_OPS_KEY_NAME > DIRLESS_OPS_KEY > read from server via SSH
        #
        # Without --env:
        #   - assumes port 5000 is already reachable (running on the ops machine itself)
        #   - API key: DIRLESS_OPS_KEY > read directly from local config file
        def self.from_env(
          env_name : String?,
          ssh_key_path : String? = nil,
          ssh_user : String? = nil,
        ) : Config
          key_path = ssh_key_path || ENV["DIRLESS_OPS_SSH_KEY"]? || DEFAULT_SSH_KEY
          user = ssh_user || DEFAULT_SSH_USER

          if env_name && !env_name.empty?
            host = Tunnel.host_for(env_name) || begin
              STDERR.puts "Error: unknown environment '#{env_name}'."
              STDERR.puts "Valid environments: #{Tunnel::HOSTS.keys.join(", ")}"
              exit 1
            end

            local_port = Tunnel.local_port_for(env_name)
            url = "http://localhost:#{local_port}"

            suffix = env_name.upcase
            api_key = ENV["DIRLESS_OPS_KEY_#{suffix}"]? ||
                      ENV["DIRLESS_OPS_KEY"]? ||
                      fetch_api_key(host, user, key_path, env_name)

            new(url, api_key, env_name, host, key_path, user, local_port)
          else
            url = "http://localhost:#{Tunnel::REMOTE_PORT}"
            api_key = ENV["DIRLESS_OPS_KEY"]? || read_local_api_key
            new(url, api_key)
          end
        end

        # Read the API key directly from the local ops config file.
        # Used when running on the ops machine itself (no --env given).
        private def self.read_local_api_key : String
          unless File.exists?(REMOTE_CONFIG)
            STDERR.puts "Error: #{REMOTE_CONFIG} not found."
            STDERR.puts "Are you on the ops machine? If not, use --env prod or --env staging."
            exit 1
          end

          key = File.read_lines(REMOTE_CONFIG).find(&.starts_with?("key =")).try(&.split('"')[1]?)

          unless key
            STDERR.puts "Error: key not found in #{REMOTE_CONFIG}."
            exit 1
          end

          key
        end

        # SSH into *host* and extract the API key from the remote ops config file.
        # The result is cached in ~/.cache/dirless-ops-cli/<env>.key for 12 hours.
        private def self.fetch_api_key(host : String, user : String, key_path : String, env_name : String) : String
          cache_file = "#{Path.home}/.cache/dirless-ops-cli/#{env_name}.key"
          ttl = 12 * 3600

          if File.exists?(cache_file)
            age = (Time.utc - File.info(cache_file).modification_time).total_seconds
            if age < ttl
              key = File.read(cache_file).strip
              return key unless key.empty?
            end
          end

          print "Reading API key from #{host}... "
          STDOUT.flush

          output = IO::Memory.new
          status = Process.run(
            "ssh",
            [
              "-i", key_path,
              "-p", Tunnel::SSH_PORT.to_s,
              "-o", "StrictHostKeyChecking=accept-new",
              "-o", "BatchMode=yes",
              "-o", "ConnectTimeout=10",
              "-o", "IdentitiesOnly=yes",
              "#{user}@#{host}",
              "awk -F'\"' '/^key =/{print $2; exit}' #{REMOTE_CONFIG}",
            ],
            output: output,
            error: Process::Redirect::Close
          )

          unless status.success?
            puts "failed."
            STDERR.puts "Error: could not SSH into #{host} to read the API key."
            STDERR.puts "Check that #{key_path} is the correct key for #{user}@#{host}."
            exit 1
          end

          key = output.to_s.strip
          if key.empty?
            puts "failed."
            STDERR.puts "Error: key not found in #{REMOTE_CONFIG} on #{host}."
            exit 1
          end

          puts "ok."
          Dir.mkdir_p(File.dirname(cache_file))
          File.write(cache_file, key)
          File.chmod(cache_file, 0o600)
          key
        end
      end
    end
  end
end
