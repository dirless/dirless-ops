class Customers::Show < BrowserAction
  get "/customers/:name" do
    customer = daemon.customer(name)
    node_statuses = daemon.customer_status(name).try(&.nodes) || [] of Dirless::Ops::WebUI::NodeStatusResponse
    html Customers::ShowPage, customer: customer, node_statuses: node_statuses
  rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
    if ex.status == 404
      flash.failure = "Customer #{name} not found"
      redirect to: Customers::Index
    else
      raise ex
    end
  end

  private def name : String
    route_params["name"]
  end
end
