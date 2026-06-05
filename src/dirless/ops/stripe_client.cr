require "http/client"
require "uri"
require "json"

module Dirless
  module Ops
    class StripeClient
      API_BASE = "https://api.stripe.com"

      def initialize(@secret_key : String)
      end

      def create_checkout_session(customer_id : String, price_id : String, customer_name : String, plan : String, success_url : String, cancel_url : String) : String
        form = URI::Params.build do |params|
          params.add("customer", customer_id)
          params.add("mode", "subscription")
          params.add("line_items[0][price]", price_id)
          params.add("line_items[0][quantity]", "1")
          params.add("success_url", success_url)
          params.add("cancel_url", cancel_url)
          params.add("metadata[customer_name]", customer_name)
          params.add("metadata[plan]", plan)
        end

        response = HTTP::Client.post(
          "#{API_BASE}/v1/checkout/sessions",
          headers: HTTP::Headers{
            "Authorization" => "Bearer #{@secret_key}",
            "Content-Type"  => "application/x-www-form-urlencoded",
          },
          body: form
        )

        parsed = JSON.parse(response.body)
        unless response.status.success?
          msg = parsed["error"]?.try(&.["message"]?.try(&.as_s)) || "unknown error"
          raise "Stripe API error (#{response.status_code}): #{msg}"
        end

        parsed["url"].as_s
      end

      def retrieve_checkout_session(session_id : String) : {payment_status: String, customer_name: String, plan: String}
        response = HTTP::Client.get(
          "#{API_BASE}/v1/checkout/sessions/#{session_id}",
          headers: HTTP::Headers{"Authorization" => "Bearer #{@secret_key}"}
        )

        parsed = JSON.parse(response.body)
        unless response.status.success?
          msg = parsed["error"]?.try(&.["message"]?.try(&.as_s)) || "unknown error"
          raise "Stripe API error (#{response.status_code}): #{msg}"
        end

        {
          payment_status: parsed["payment_status"].as_s,
          customer_name:  parsed["metadata"]["customer_name"].as_s,
          plan:           parsed["metadata"]["plan"].as_s,
        }
      end

      def create_customer(email : String, name : String, metadata : Hash(String, String) = {} of String => String) : String
        form = URI::Params.build do |params|
          params.add("email", email)
          params.add("name", name)
          metadata.each { |k, v| params.add("metadata[#{k}]", v) }
        end

        response = HTTP::Client.post(
          "#{API_BASE}/v1/customers",
          headers: HTTP::Headers{
            "Authorization" => "Bearer #{@secret_key}",
            "Content-Type"  => "application/x-www-form-urlencoded",
          },
          body: form
        )

        parsed = JSON.parse(response.body)
        unless response.status.success?
          msg = parsed["error"]?.try(&.["message"]?.try(&.as_s)) || "unknown error"
          raise "Stripe API error (#{response.status_code}): #{msg}"
        end

        parsed["id"].as_s
      end
    end
  end
end
