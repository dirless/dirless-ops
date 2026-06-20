class Portal::BootstrapConfirm < Lucky::Action
  accepted_formats [:html]

  get "/directory/bootstrap/confirm" do
    token = params.get?(:token).to_s.strip

    if token.empty?
      flash.failure = "Invalid registration link."
      redirect to: Portal::DirectoryShow
    else
      begin
        customer_name, username = daemon.confirm_bootstrap(token)
        flash.success = "SSH certificate registration complete for #{username}. You can now run 'dirless-connect ssh login'."
        redirect to: Portal::DirectoryShow
      rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
        case ex.status
        when 410
          flash.failure = "This registration link has already been used or has expired."
        when 404
          flash.failure = "Registration link is invalid."
        else
          flash.failure = "Registration failed: #{ex.message}"
        end
        redirect to: Portal::DirectoryShow
      end
    end
  end

  private def daemon
    Dirless::Ops::WebUI::DaemonClient.new
  end
end
