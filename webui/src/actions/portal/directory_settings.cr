class Portal::DirectorySettings < PortalAction
  post "/directory/settings" do
    ttl_value = params.get?(:ttl_value).to_s.strip
    ttl_unit = params.get?(:ttl_unit).to_s.strip
    n = ttl_value.to_i64?

    if !n || n <= 0
      flash.failure = "Please enter a valid number."
    else
      multiplier = ttl_unit == "days" ? 86_400_i64 : 3_600_i64
      cert_ttl_seconds = n * multiplier

      if cert_ttl_seconds < 3_600_i64 || cert_ttl_seconds > 2_592_000_i64
        flash.failure = "TTL must be between 1 hour and 30 days."
      else
        begin
          daemon.update_cert_ttl(portal_customer_name, cert_ttl_seconds)
          flash.success = "Certificate TTL updated."
        rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
          flash.failure = "Could not save settings: #{ex.message}"
        end
      end
    end

    redirect Portal::SettingsShow
  end
end
