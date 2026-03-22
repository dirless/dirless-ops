class Customers::Show < BrowserAction
  get "/customers/:name" do
    customer = daemon.customer(name)
    node_statuses = daemon.customer_status(name).try(&.nodes) || [] of Dirless::Ops::WebUI::NodeStatusResponse
    html Customers::ShowPage, customer: customer, node_statuses: node_statuses
  end

  private def name : String
    route_params["name"]
  end
end
