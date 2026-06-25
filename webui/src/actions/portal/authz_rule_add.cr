class Portal::AuthzRuleAdd < PortalAction
  post "/settings/authz-rule-add" do
    group = params.get?(:group).to_s.strip
    host  = params.get?(:host).to_s.strip

    unless group.empty? || host.empty?
      begin
        current = daemon.fetch_authz_config(portal_customer_name)
        new_rule = Dirless::Ops::WebUI::HostGroupRuleResponse.from_json(
          %({"group":#{group.to_json},"host":#{host.to_json}})
        )
        updated_rules = current.host_group_rules + [new_rule]
        daemon.update_authz_config(portal_customer_name, current.enforce_group_memberships, updated_rules)
        flash.success = "Rule added: group \"#{group}\" on host \"#{host}\"."
      rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
        flash.failure = "Could not add rule: #{ex.message}"
      end
    else
      flash.failure = "Group name and hostname are both required."
    end

    redirect Portal::SettingsShow
  end
end
