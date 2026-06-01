class Portal::DirectoryShow < PortalAction
  get "/directory" do
    # Always re-check provisioned status from the API — session can be stale.
    customer = daemon.customer(portal_customer_name)
    actually_provisioned = customer.provisioned == true
    if actually_provisioned && !portal_provisioned
      session.set(:portal_provisioned, "true")
    end

    if actually_provisioned
      name = portal_customer_name
      cloud_blob = daemon.fetch_cloud_snapshot(name)
      local_blob = daemon.fetch_local_snapshot(name)
      html Portal::DirectoryPage,
        email: portal_email,
        company: portal_company,
        cloud_snapshot_blob: cloud_blob,
        local_snapshot_blob: local_blob
    else
      html Portal::DirectoryPage,
        email: portal_email,
        company: portal_company,
        cloud_snapshot_blob: nil,
        local_snapshot_blob: nil,
        provisioned: false
    end
  rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
    html Portal::DirectoryPage,
      email: portal_email,
      company: portal_company,
      cloud_snapshot_blob: nil,
      local_snapshot_blob: nil,
      backend_error: ex.message
  end
end
