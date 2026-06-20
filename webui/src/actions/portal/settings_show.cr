class Portal::SettingsShow < PortalAction
  get "/settings" do
    cert_ttl_seconds = nil
    begin
      customer = daemon.customer(portal_customer_name)
      cert_ttl_seconds = customer.cert_ttl_seconds
    rescue Dirless::Ops::WebUI::DaemonClient::Error
    end

    html Portal::SettingsPage,
      email: portal_email,
      company: portal_company,
      cert_ttl_seconds: cert_ttl_seconds
  end
end
