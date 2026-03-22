class Customers::Delete < BrowserAction
  delete "/customers/:name" do
    daemon.delete_customer(route_params["name"])
    flash.success = "Customer deleted"
    redirect to: Customers::Index
  end
end
