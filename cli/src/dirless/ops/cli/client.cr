require "http/client"
require "json"
require "./config"

module Dirless
  module Ops
    module CLI
      class Client
        def initialize(@config : Config)
        end

        def get(path : String) : JSON::Any
          response = http_client.get(path, headers: auth_headers)
          check!(response)
          JSON.parse(response.body)
        end

        def post(path : String, body : Hash) : JSON::Any
          response = http_client.post(path, headers: json_headers, body: body.to_json)
          check!(response)
          JSON.parse(response.body)
        end

        def patch(path : String, body : Hash) : JSON::Any
          response = http_client.patch(path, headers: json_headers, body: body.to_json)
          check!(response)
          JSON.parse(response.body)
        end

        def delete(path : String) : Nil
          response = http_client.delete(path, headers: auth_headers)
          check!(response)
        end

        private def http_client : HTTP::Client
          HTTP::Client.new(URI.parse(@config.url))
        end

        private def auth_headers : HTTP::Headers
          HTTP::Headers{"Authorization" => "Bearer #{@config.api_key}"}
        end

        private def json_headers : HTTP::Headers
          HTTP::Headers{
            "Authorization" => "Bearer #{@config.api_key}",
            "Content-Type"  => "application/json",
          }
        end

        private def check!(response : HTTP::Client::Response) : Nil
          return if response.success?
          begin
            parsed = JSON.parse(response.body)
            STDERR.puts "Error (#{response.status_code}): #{parsed["error"]?}"
          rescue
            STDERR.puts "Error (#{response.status_code}): #{response.body}"
          end
          exit 1
        end
      end
    end
  end
end
