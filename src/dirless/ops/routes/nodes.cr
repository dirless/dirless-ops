require "grip"
require "json"
require "../models/node"

module Dirless
  module Ops
    module Controllers
      class ListNodes
        include Grip::Controllers::HTTP

        def get(context : Context) : Context
          nodes = Node.all
          context.put_status(200).json(nodes.map(&.to_response)).halt
        end
      end

      class CreateNode
        include Grip::Controllers::HTTP

        def post(context : Context) : Context
          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON: #{ex.message}"}).halt
          end

          name = parsed["name"]?.try(&.as_s)
          ip = parsed["ip"]?.try(&.as_s)
          region = parsed["region"]?.try(&.as_s)
          provider = parsed["provider"]?.try(&.as_s) || "atlanticnet"

          unless name && ip && region
            return context.put_status(422).json({"error" => "name, ip, and region are required"}).halt
          end

          if Node.where(name: name).exists?
            return context.put_status(409).json({"error" => "node already exists"}).halt
          end

          is_primary = parsed["is_primary"]?.try { |v| v.as_bool? || v.as_s? == "true" } || false

          node = Node.new(
            name: name,
            ip: ip,
            region: region,
            provider: provider,
            is_primary: is_primary,
          )

          unless node.save
            return context.put_status(422).json({"error" => node.errors.map(&.message).join(", ")}).halt
          end

          context.put_status(201).json(node.to_response).halt
        end
      end

      class GetNode
        include Grip::Controllers::HTTP

        def get(context : Context) : Context
          name = context.fetch_path_params["name"]
          node = Node.find_by(name: name)

          unless node
            return context.put_status(404).json({"error" => "node not found"}).halt
          end

          context.put_status(200).json(node.to_response).halt
        end
      end

      class UpdateNode
        include Grip::Controllers::HTTP

        def patch(context : Context) : Context
          name = context.fetch_path_params["name"]
          node = Node.find_by(name: name)

          unless node
            return context.put_status(404).json({"error" => "node not found"}).halt
          end

          body = context.request.body.try(&.gets_to_end) || ""
          begin
            parsed = JSON.parse(body)
          rescue ex : JSON::ParseException
            return context.put_status(400).json({"error" => "malformed JSON: #{ex.message}"}).halt
          end

          parsed["ip"]?.try { |v| v.as_s?.try { |s| node.ip = s } }
          parsed["region"]?.try { |v| v.as_s?.try { |s| node.region = s } }
          parsed["provider"]?.try { |v| v.as_s?.try { |s| node.provider = s } }
          parsed["is_primary"]?.try { |v|
            node.is_primary = v.as_bool? || v.as_s? == "true"
          }

          unless node.save
            return context.put_status(422).json({"error" => node.errors.map(&.message).join(", ")}).halt
          end

          context.put_status(200).json(node.to_response).halt
        end
      end

      class DeleteNode
        include Grip::Controllers::HTTP

        def delete(context : Context) : Context
          name = context.fetch_path_params["name"]
          node = Node.find_by(name: name)

          unless node
            return context.put_status(404).json({"error" => "node not found"}).halt
          end

          node.destroy
          context.put_status(204).halt
        end
      end
    end
  end
end
