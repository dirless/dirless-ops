class Customers::Index < BrowserAction
  get "/customers" do
    customers = daemon.customers
    html Customers::IndexPage, customers: customers
  end
end
