require "log"
require "http/client"
require "json"

module Dirless
  module Ops
    module Deployer
      Log = ::Log.for("dirless-deployer")

      class Runner
        @ansible_inventory : String
        @ansible_playbook : String
        @api_url : String

        def initialize(@config : Config, @notifier : Notifier)
          @ansible_inventory = @config.ansible_inventory || raise "deployer.ansible_inventory not set in config"
          @ansible_playbook = @config.ansible_playbook || raise "deployer.ansible_playbook not set in config"
          @api_url = "http://#{@config.host}:#{@config.port}"
        end

        def run
          job_data = claim_next_job
          unless job_data
            Log.info { "No pending provision jobs" }
            return
          end

          job_id = job_data["id"].as_s.to_i64
          customer_name = job_data["customer_name"].as_s
          hmac_secret = job_data["hmac_secret"].as_s

          Log.info { "Processing provision job ##{job_id} for customer #{customer_name}" }

          success, output = run_ansible(customer_name, hmac_secret)

          if success
            dns_ok, dns_output = update_dns
            unless dns_ok
              Log.warn { "DNS update failed (non-fatal): #{dns_output}" }
            end
            api_patch("/v1/provision-jobs/#{job_id}", {"status" => "completed"})
            notify_environment_ready(customer_name)
            Log.info { "Provision job ##{job_id} completed successfully" }
          else
            notify_provisioning_failed(customer_name)
            truncated = output.size > 4096 ? output[-4096..] : output
            api_patch("/v1/provision-jobs/#{job_id}", {"status" => "failed", "error" => truncated})
            Log.error { "Provision job ##{job_id} failed: #{truncated}" }
          end
        end

        ANSIBLE_TIMEOUT  = 3.minutes
        STUCK_THRESHOLD  = ANSIBLE_TIMEOUT + 1.minute
        MAX_RESET_COUNT  = 3

        # Returns a JSON::Any hash with id, customer_name, hmac_secret — or nil if nothing to do.
        # All reads/writes go through the API to avoid TPDB multi-process stale cache issues.
        def claim_next_job : JSON::Any?
          # Auto-reset stuck in_progress jobs.
          cutoff = Time.utc - STUCK_THRESHOLD
          in_progress = api_get("/v1/provision-jobs?status=in_progress").as_a
          in_progress.each do |j|
            started = j["started_at"].as_s?
            next unless started
            started_time = Time.parse_rfc3339(started) rescue next
            next unless started_time < cutoff
            job_id = j["id"].as_i64
            reset_count = (j["reset_count"]?.try { |v| v.as_i64? || v.as_i? } || 0) + 1
            api_patch("/v1/provision-jobs/#{job_id}", {"status" => "pending"})
            Log.warn { "Reset stuck provision job ##{job_id} (reset ##{reset_count})" }
            if reset_count >= MAX_RESET_COUNT
              notify_stuck_job(j["customer_name"].as_s, job_id, reset_count)
            end
          end

          # Find oldest pending job for a verified customer.
          pending = api_get("/v1/provision-jobs?status=pending").as_a
          pending.sort_by { |j| j["created_at"].as_s? || "" }.each do |j|
            customer_name = j["customer_name"].as_s
            customer = api_get("/v1/customers/#{customer_name}") rescue next
            next unless customer["email_verified"].as_bool? == true

            job_id = j["id"].as_i64
            # Claim it by marking in_progress.
            api_patch("/v1/provision-jobs/#{job_id}", {"status" => "in_progress"})

            # Fetch full customer data for hmac_secret.
            return JSON.parse({
              "id"            => job_id.to_s,
              "customer_name" => customer_name,
              "hmac_secret"   => customer["hmac_secret"].as_s,
            }.to_json)
          end

          nil
        end

        def run_ansible(customer_name : String, hmac_secret : String) : {Bool, String}
          customer_json = {
            customers:      [{name: customer_name, hmac_secret: hmac_secret}],
            keepass_master: "",
            ops_key:        @config.api_key,
          }.to_json

          # Write vars to a mode-600 temp file rather than passing via stdin.
          # Ansible resolves /dev/stdin to the actual pipe path (/proc/PID/fd/pipe:...)
          # on some systems, which it then can't open via its file-access layer.
          tmp_vars = "/tmp/dirless-provision-#{Random::Secure.hex(8)}.json"
          File.write(tmp_vars, customer_json)
          File.chmod(tmp_vars, 0o600)

          args = [
            "-i", @ansible_inventory,
            @ansible_playbook,
            "-e", "@#{tmp_vars}",
            "--diff",
          ]
          if ops_url = @config.ansible_ops_url
            args << "-e" << "ops_url=#{ops_url}"
          end

          Log.info { "Running: ansible-playbook for customer #{customer_name}" }

          output = IO::Memory.new
          timed_out = false
          process = Process.new(
            "ansible-playbook",
            args: args,
            input: Process::Redirect::Close,
            output: output,
            error: output,
          )

          spawn do
            sleep ANSIBLE_TIMEOUT
            unless process.terminated?
              timed_out = true
              process.signal(Signal::TERM)
              sleep 10.seconds
              process.signal(Signal::KILL) unless process.terminated?
            end
          end

          status = process.wait

          result = output.to_s
          truncated = result.size > 4096 ? result[-4096..] : result
          if timed_out
            {false, "ansible-playbook timed out after #{ANSIBLE_TIMEOUT.total_minutes.to_i} minutes\n#{truncated}"}
          else
            {status.success?, truncated}
          end
        rescue ex : Exception
          {false, ex.message || "unknown error"}
        ensure
          File.delete(tmp_vars) rescue nil if tmp_vars
        end

        private def api_get(path : String) : JSON::Any
          response = HTTP::Client.get(
            "#{@api_url}#{path}",
            headers: HTTP::Headers{"Authorization" => "Bearer #{@config.api_key}"}
          )
          JSON.parse(response.body)
        end

        private def api_patch(path : String, body : Hash(String, String)) : Nil
          HTTP::Client.patch(
            "#{@api_url}#{path}",
            headers: HTTP::Headers{
              "Authorization" => "Bearer #{@config.api_key}",
              "Content-Type"  => "application/json",
            },
            body: body.to_json
          )
        rescue ex
          Log.error { "API PATCH #{path} failed: #{ex.message}" }
        end

        def update_dns : {Bool, String}
          Log.info { "Updating DNS records" }
          output = IO::Memory.new
          status = Process.run(
            "/usr/local/bin/update-dns",
            output: output,
            error: output,
          )
          result = output.to_s
          if status.success?
            Log.info { "DNS update succeeded" }
          end
          {status.success?, result}
        rescue ex : Exception
          {false, ex.message || "unknown error"}
        end

        private def notify_environment_ready(customer_name : String)
          customer = api_get("/v1/customers/#{customer_name}") rescue return
          email = customer["email"].as_s? || return
          company = customer["company"].as_s? || customer_name
          @notifier.environment_ready(email, company, customer_name)
        end

        private def notify_provisioning_failed(customer_name : String)
          customer = api_get("/v1/customers/#{customer_name}") rescue return
          email = customer["email"].as_s? || return
          company = customer["company"].as_s? || customer_name
          @notifier.provisioning_failed(email, company)
        end

        private def notify_stuck_job(customer_name : String, job_id : Int64, reset_count : Int32 | Int64)
          alert_email = @config.ops_alert_email || return
          @notifier.ops_alert(
            alert_email,
            "Provision job stuck: #{customer_name}",
            "Provision job ##{job_id} for customer '#{customer_name}' has been auto-reset " \
            "#{reset_count} time(s) after exceeding the #{ANSIBLE_TIMEOUT.total_minutes.to_i}-minute timeout. " \
            "Please investigate — further resets will continue but the job may need manual intervention."
          )
        end
      end
    end
  end
end
