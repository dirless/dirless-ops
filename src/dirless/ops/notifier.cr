require "log"

module Dirless
  module Ops
    class Notifier
      Log = ::Log.for("dirless-notifier")

      FROM = "Dirless <info@dirless.com>"

      def initialize(@spool_dir : String, @ops_alert_email : String? = nil,
                     @portal_url : String = "https://portal.dirless.com")
      end

      def welcome(email : String, company : String, customer_name : String)
        body = <<-BODY
        Hi there,

        Thank you for signing up for Dirless!

        We've sent a separate email to verify your address. Your environment
        will be provisioned as soon as you confirm — just click the
        verification link.

        If you have any questions, just reply to this email.

        — The Dirless team
        BODY
        queue(email, "Welcome to Dirless", body)
      end

      def verify_email(email : String, token : String)
        link = "#{@portal_url}/verify-email?token=#{token}"
        body = <<-BODY
        Hi there,

        Please verify your email address by clicking the link below:

          #{link}

        If you didn't create a Dirless account, you can safely ignore this email.

        — The Dirless team
        BODY
        queue(email, "Verify your Dirless email address", body)
      end

      def environment_ready(email : String, company : String, customer_name : String)
        body = <<-BODY
        Hi there,

        Great news — your Dirless environment is ready.

        Dashboard: #{@portal_url}

        If you have any questions, just reply to this email.

        — The Dirless team
        BODY
        queue(email, "Your Dirless environment is ready", body)
      end

      def provisioning_failed(email : String, company : String)
        body = <<-BODY
        Hi there,

        We ran into an issue setting up your Dirless environment.
        Our team has been notified and is looking into it.

        We'll follow up with you shortly.

        — The Dirless team
        BODY
        queue(email, "Issue with your Dirless environment setup", body)
      end

      def account_deleted(email : String, company : String)
        body = <<-BODY
        Hi there,

        Your Dirless account for #{company} has been deleted.

        If you believe this was done in error, please reply to this email.

        — The Dirless team
        BODY
        queue(email, "Your Dirless account has been deleted", body)
      end

      def registration_error(email : String, ex : Exception)
        to = @ops_alert_email
        return unless to
        backtrace = ex.backtrace?.try(&.first(8).join("\n")) || "(no backtrace)"
        body = <<-BODY
        A registration attempt failed with an unhandled exception.

        Email:    #{email}
        Error:    #{ex.class}: #{ex.message}
        Time:     #{Time.utc.to_rfc3339}

        Backtrace:
        #{backtrace}

        — Dirless ops daemon
        BODY
        queue(to, "⚠️ Registration error for #{email}", body)
      end

      def probe_failing(node_name : String, node_ip : String, error : String, count : Int32)
        to = @ops_alert_email
        return unless to
        body = <<-BODY
        Node probe has failed #{count} consecutive times.

        Node:  #{node_name}
        IP:    #{node_ip}
        Error: #{error}
        Time:  #{Time.utc.to_rfc3339}

        — Dirless node prober
        BODY
        queue(to, "Node probe failing: #{node_name} (#{count} consecutive failures)", body)
      end

      def node_down(node_name : String, node_ip : String, error : String)
        to = @ops_alert_email
        return unless to
        body = <<-BODY
        Node down alert.

        Node:  #{node_name}
        IP:    #{node_ip}
        Error: #{error}
        Time:  #{Time.utc.to_rfc3339}

        — Dirless node prober
        BODY
        queue(to, "Node down: #{node_name}", body)
      end

      def ops_alert(to : String, subject : String, body : String)
        queue(to, subject, body)
      end

      private def queue(to : String, subject : String, body : String)
        spawn do
          begin
            write_email(to, subject, body)
          rescue ex
            Log.error { "Failed to queue email to #{to} (#{subject}): #{ex.message}" }
          end
        end
      end

      private def write_email(to : String, subject : String, body : String)
        tmp = File.join(@spool_dir, "#{Random::Secure.hex(8)}.eml.tmp")
        final = tmp.sub(".eml.tmp", ".eml")

        content = String.build do |io|
          io << "From: #{FROM}\n"
          io << "To: #{to}\n"
          io << "Subject: #{subject}\n"
          io << "MIME-Version: 1.0\n"
          io << "Content-Type: text/plain; charset=UTF-8\n"
          io << "\n"
          io << body
        end

        File.write(tmp, content)
        File.rename(tmp, final)
        Log.info { "Queued email to #{to}: #{subject}" }
      end
    end
  end
end
