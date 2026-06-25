class Portal::AuthzToggle < PortalAction
  post "/settings/authz-toggle" do
    enforce = params.get?(:enforce) == "true"

    begin
      current = daemon.fetch_authz_config(portal_customer_name)
      daemon.update_authz_config(portal_customer_name, enforce, current.host_group_rules)
      flash.success = enforce ? "Login enforcement enabled." : "Login enforcement disabled."
    rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
      flash.failure = "Could not update setting: #{ex.message}"
    end

    redirect Portal::SettingsShow
  end
end
