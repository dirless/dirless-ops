class Portal::DirectoryRecoverKey < PortalAction
  post "/directory/recover-key" do
    public_key = params.get(:age_public_key).strip
    if public_key.starts_with?("age1")
      daemon.delete_local_snapshot(portal_customer_name)
      daemon.register_age_public_key(portal_customer_name, public_key)
      flash.success = "Key reset complete. Local users have been cleared - re-add them below. " \
                      "Re-enroll your syncer with: dirless-cli enroll --overwrite-existing"
    else
      flash.failure = "Invalid age public key."
    end
    redirect to: Portal::DirectoryShow
  rescue ex : Lucky::MissingParamError
    flash.failure = "Missing public key."
    redirect to: Portal::DirectoryShow
  rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
    flash.failure = "Key recovery failed: #{ex.message}"
    redirect to: Portal::DirectoryShow
  end
end
