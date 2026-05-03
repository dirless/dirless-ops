require "log"

module Dirless
  module Ops
    module Deployer
      Log = ::Log.for("dirless-deployer")

      class Runner
        @ansible_inventory : String
        @ansible_playbook : String

        def initialize(@config : Config, @notifier : Notifier)
          @ansible_inventory = @config.ansible_inventory || raise "deployer.ansible_inventory not set in config"
          @ansible_playbook = @config.ansible_playbook || raise "deployer.ansible_playbook not set in config"
        end

        def run
          job = claim_next_job
          unless job
            Log.info { "No pending provision jobs" }
            return
          end

          Log.info { "Processing provision job ##{job.id} for customer #{job.customer_name}" }

          customer = Customer.find_by(name: job.customer_name)
          unless customer
            fail_job(job, "Customer '#{job.customer_name}' not found in database")
            return
          end

          success, output = run_ansible(customer.name, customer.hmac_secret)

          if success
            dns_ok, dns_output = update_dns
            unless dns_ok
              Log.warn { "DNS update failed (non-fatal): #{dns_output}" }
            end
            complete_job(job)
            mark_account_provisioned(job.customer_name)
            notify_environment_ready(job.customer_name)
            Log.info { "Provision job ##{job.id} completed successfully" }
          else
            notify_provisioning_failed(job.customer_name)
            fail_job(job, output)
            Log.error { "Provision job ##{job.id} failed: #{output}" }
          end
        end

        def claim_next_job : ProvisionJob?
          db = Granite::Connections["sqlite"].not_nil![:writer].database

          row = db.query_one?(
            "SELECT id FROM provision_jobs WHERE status = 'pending' ORDER BY created_at ASC LIMIT 1",
            as: Int64,
          )
          return nil unless row

          now = Time.utc.to_s("%Y-%m-%d %H:%M:%S")
          result = db.exec(
            "UPDATE provision_jobs SET status = 'in_progress', started_at = ? WHERE id = ? AND status = 'pending'",
            now, row,
          )

          return nil if result.rows_affected == 0

          ProvisionJob.find!(row)
        end

        ANSIBLE_TIMEOUT = 10.minutes

        def run_ansible(customer_name : String, hmac_secret : String) : {Bool, String}
          # Pass customer data via stdin (@/dev/stdin) instead of CLI args
          # to avoid exposing secrets in /proc/*/cmdline and logs.
          customer_json = {customers: [{name: customer_name, hmac_secret: hmac_secret}]}.to_json

          args = [
            "-i", @ansible_inventory,
            @ansible_playbook,
            "-e", "@/dev/stdin",
            "--diff",
          ]

          Log.info { "Running: ansible-playbook for customer #{customer_name}" }

          output = IO::Memory.new
          timed_out = false
          process = Process.new(
            "ansible-playbook",
            args: args,
            input: Process::Redirect::Pipe,
            output: output,
            error: output,
          )
          process.input.print(customer_json)
          process.input.close

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
        end

        def complete_job(job : ProvisionJob)
          job.status = "completed"
          job.completed_at = Time.utc
          job.save
        end

        def fail_job(job : ProvisionJob, error : String)
          job.status = "failed"
          job.error = error.size > 4096 ? error[-4096..] : error
          job.completed_at = Time.utc
          job.save
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
          account = CustomerAccount.find_by(customer_name: customer_name)
          return unless account
          @notifier.environment_ready(account.email, account.company || customer_name, customer_name)
        end

        private def notify_provisioning_failed(customer_name : String)
          account = CustomerAccount.find_by(customer_name: customer_name)
          return unless account
          @notifier.provisioning_failed(account.email, account.company || customer_name)
        end

        def mark_account_provisioned(customer_name : String)
          account = CustomerAccount.find_by(customer_name: customer_name)
          if account
            account.provisioned = true
            account.save
          end
        end
      end
    end
  end
end
