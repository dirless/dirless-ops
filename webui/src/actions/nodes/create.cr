class Nodes::Create < BrowserAction
  post "/nodes" do
    body = {} of String => String
    body["name"] = params.get(:name)
    body["ip"] = params.get(:ip)
    body["region"] = params.get(:region)
    body["provider"] = params.get?(:provider).try { |v| v.empty? ? "atlanticnet" : v } || "atlanticnet"
    body["is_primary"] = params.get?(:is_primary) == "true" ? "true" : "false"

    node = daemon.create_node(body)
    flash.success = "Node #{node.name} added"
    redirect to: Nodes::Index
  end
end
