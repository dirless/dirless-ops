class Home::Index < BrowserAction
  get "/" do
    statuses = daemon.status
    html Home::IndexPage, statuses: statuses
  end
end
