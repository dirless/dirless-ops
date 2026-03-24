require "grip"
require "json"
require "../models/provision_job"
require "../models/customer_account"

module Dirless
  module Ops
    module Controllers
      class ListProvisionJobs
        include Grip::Controllers::HTTP

        def get(context : Context) : Context
          status = context.request.query_params["status"]?
          jobs = if status
                   ProvisionJob.where(status: status).select
                 else
                   ProvisionJob.all
                 end
          context.put_status(200).json(jobs.map(&.to_response)).halt
        end
      end

      class GetProvisionJob
        include Grip::Controllers::HTTP

        def get(context : Context) : Context
          id = context.fetch_path_params["id"]
          job = ProvisionJob.find(id)
          unless job
            return context.put_status(404).json({"error" => "not found"}).halt
          end
          context.put_status(200).json(job.to_response).halt
        end
      end

      VALID_JOB_STATUSES = {"pending", "in_progress", "completed", "failed"}

      class UpdateProvisionJob
        include Grip::Controllers::HTTP

        def patch(context : Context) : Context
          id = context.fetch_path_params["id"]
          job = ProvisionJob.find(id)
          unless job
            return context.put_status(404).json({"error" => "not found"}).halt
          end

          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON"}).halt
          end

          if s = parsed["status"]?.try(&.as_s)
            unless VALID_JOB_STATUSES.includes?(s)
              return context.put_status(422).json({"error" => "invalid status '#{s}', must be one of: #{VALID_JOB_STATUSES.join(", ")}"}).halt
            end
            job.status = s
            case s
            when "in_progress"
              job.started_at = Time.utc
            when "completed", "failed"
              job.completed_at = Time.utc
            end
          end

          if e = parsed["error"]?.try(&.as_s)
            job.error = e
          end

          unless job.save
            return context.put_status(422).json({"error" => job.errors.map(&.message).join(", ")}).halt
          end

          # Mark the customer account as provisioned when the job completes
          if job.status == "completed"
            account = CustomerAccount.find_by(customer_name: job.customer_name)
            if account
              account.provisioned = true
              account.save
            end
          end

          context.put_status(200).json(job.to_response).halt
        end
      end
    end
  end
end
