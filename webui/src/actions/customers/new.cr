class Customers::New < BrowserAction
  get "/customers/new" do
    html Customers::NewPage, errors: {} of String => String, values: {} of String => String
  end
end
