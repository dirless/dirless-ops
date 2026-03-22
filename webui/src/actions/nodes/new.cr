class Nodes::New < BrowserAction
  get "/nodes/new" do
    html Nodes::NewPage
  end
end
