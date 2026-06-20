require "socket"

module Dirless
  module Ops
    module CLI
      module Tunnel
        SSH_PORT    = 39124
        REMOTE_PORT =  5000 # port the ops API listens on remotely
        LOCAL_HOST  = "127.0.0.1"

        # Fixed host mappings — these never change.
        HOSTS = {
          "prod"    => "admin.dirless.com",
          "staging" => "admin.staging.dirless.com",
        }

        # Each named environment gets its own local port so a running dev instance
        # on port 5000 never causes --env prod to silently hit the wrong server.
        LOCAL_PORTS = {
          "prod"    => 15000,
          "staging" => 15001,
        }

        # Ensure the API is reachable via the correct URL in *config*.
        # - No env (remote_host is nil): expects port 5000 already open (on the ops machine).
        # - With env: always opens a fresh tunnel on the env-specific local port.
        def self.ensure_ready(config : Config) : Nil
          host = config.remote_host
          return unless host # running directly on the ops machine

          local_port = config.local_port

          return if port_open?(local_port) # reuse an existing tunnel from this session

          open_tunnel(host, config.ssh_user, config.ssh_key_path, local_port)
          wait_for_port(local_port)
        end

        # Returns the SSH hostname for the given environment name, or nil.
        def self.host_for(env_name : String) : String?
          HOSTS[env_name]?
        end

        # Returns the local tunnel port for the given environment name.
        # Falls back to REMOTE_PORT (5000) when no env is given.
        def self.local_port_for(env_name : String?) : Int32
          return REMOTE_PORT unless env_name
          LOCAL_PORTS[env_name]? || REMOTE_PORT
        end

        private def self.port_open?(port : Int32) : Bool
          TCPSocket.new(LOCAL_HOST, port).close
          true
        rescue
          false
        end

        private def self.open_tunnel(host : String, user : String, key_path : String, local_port : Int32) : Nil
          args = [
            "-i", key_path,
            "-p", SSH_PORT.to_s,
            "-N",
            "-L", "#{local_port}:#{LOCAL_HOST}:#{REMOTE_PORT}",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "IdentitiesOnly=yes",
          ]
          args << "#{user}@#{host}"

          process = Process.new(
            "ssh", args,
            input: Process::Redirect::Close,
            output: Process::Redirect::Close,
            error: Process::Redirect::Close
          )

          at_exit { process.signal(:term) rescue nil }

          print "Opening SSH tunnel to #{host} (local port #{local_port})... "
          STDOUT.flush
        end

        private def self.wait_for_port(port : Int32) : Nil
          30.times do
            if port_open?(port)
              puts "ready."
              return
            end
            sleep 1.second
          end
          puts ""
          STDERR.puts "Error: SSH tunnel did not come up within 30 seconds."
          STDERR.puts "Check that the key at #{Config::DEFAULT_SSH_KEY} is correct,"
          STDERR.puts "or pass --private-ssh-key <path> to specify a different one."
          exit 1
        end
      end
    end
  end
end
