class Portal::DirectoryShow < PortalAction
  get "/directory" do
    name = portal_customer_name
    cloud_blob = daemon.fetch_cloud_snapshot(name)
    local_blob = daemon.fetch_local_snapshot(name)
    html Portal::DirectoryPage,
      email: portal_email,
      company: portal_company,
      cloud_snapshot_blob: cloud_blob,
      local_snapshot_blob: local_blob
  rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
    html Portal::DirectoryPage,
      email: portal_email,
      company: portal_company,
      cloud_snapshot_blob: nil,
      local_snapshot_blob: nil,
      backend_error: ex.message
  end
end
