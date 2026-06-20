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
      begin
        cloud_blob = daemon.fetch_cloud_snapshot(name)
        local_blob = daemon.fetch_local_snapshot(name)
        age_public_key = daemon.fetch_age_public_key(name)
        html Portal::DirectoryPage,
          email: portal_email,
          company: portal_company,
          cloud_snapshot_blob: cloud_blob,
          local_snapshot_blob: local_blob,
          age_public_key: age_public_key
      rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
        recently_created = customer.created_at.try { |s| Time.parse_rfc3339(s) > 20.minutes.ago } || false
        html Portal::DirectoryPage,
          email: portal_email,
          company: portal_company,
          cloud_snapshot_blob: nil,
          local_snapshot_blob: nil,
          recently_created: recently_created,
          backend_error: ex.message
      end
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
      provisioned: false,
      backend_error: ex.message
  end
end
