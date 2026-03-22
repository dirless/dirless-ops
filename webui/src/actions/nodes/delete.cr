class Nodes::Delete < BrowserAction
  delete "/nodes/:name" do
    daemon.delete_node(route_params["name"])
    flash.success = "Node deleted"
    redirect to: Nodes::Index
  end
end
