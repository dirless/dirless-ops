class Portal::DirectoryRegisterKey < PortalAction
  post "/directory/register-key" do
    public_key = params.get(:age_public_key).strip
    if public_key.starts_with?("age1")
      daemon.register_age_public_key(portal_customer_name, public_key)
      flash.success = "Keypair registered. Save your private key somewhere safe — it cannot be recovered."
    else
      flash.failure = "Invalid age public key."
    end
    redirect to: Portal::DirectoryShow
  rescue ex : Lucky::MissingParamError
    flash.failure = "Missing public key."
    redirect to: Portal::DirectoryShow
  rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
    flash.failure = "Failed to register key: #{ex.message}"
    redirect to: Portal::DirectoryShow
  end
end
