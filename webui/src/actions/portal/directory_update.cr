class Portal::DirectoryUpdate < PortalAction
  post "/directory" do
    blob = params.get(:blob)
    recipient = params.get?(:recipient).to_s.strip
    daemon.push_directory_snapshot(portal_customer_name, blob, recipient)
    flash.success = "Directory saved successfully."
    redirect to: Portal::DirectoryShow
  rescue ex : Lucky::MissingParamError
    flash.failure = "Missing blob — the form was submitted without a payload."
    redirect to: Portal::DirectoryShow
  rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
    flash.failure = "Failed to save: #{ex.message}"
    redirect to: Portal::DirectoryShow
  end
end