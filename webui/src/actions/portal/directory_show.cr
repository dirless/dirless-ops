class Portal::DirectoryShow < PortalAction
  get "/directory" do
    snapshot_blob = daemon.fetch_directory_snapshot(portal_customer_name)
    html Portal::DirectoryPage,
      email: portal_email,
      company: portal_company,
      snapshot_blob: snapshot_blob
  rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
    html Portal::DirectoryPage,
      email: portal_email,
      company: portal_company,
      snapshot_blob: nil,
      backend_error: ex.message
  end
end
