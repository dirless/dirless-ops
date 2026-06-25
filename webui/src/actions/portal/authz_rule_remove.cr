class Portal::AuthzRuleRemove < PortalAction
  post "/settings/authz-rule-remove" do
    index = params.get?(:rule_index).to_s.strip.to_i?

    begin
      current = daemon.fetch_authz_config(portal_customer_name)
      if index && index >= 0 && index < current.host_group_rules.size
        updated_rules = current.host_group_rules.each_with_index.reject { |_, i| i == index }.map { |r, _| r }.to_a
        daemon.update_authz_config(portal_customer_name, current.enforce_group_memberships, updated_rules)
        flash.success = "Rule removed."
      else
        flash.failure = "Invalid rule index."
      end
    rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
      flash.failure = "Could not remove rule: #{ex.message}"
    end

    redirect Portal::SettingsShow
  end
end
