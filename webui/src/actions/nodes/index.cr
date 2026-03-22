class Nodes::Index < BrowserAction
  get "/nodes" do
    nodes = daemon.nodes
    html Nodes::IndexPage, nodes: nodes
  end
end
