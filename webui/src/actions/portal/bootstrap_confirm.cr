class Portal::BootstrapConfirm < Lucky::Action
  accepted_formats [:html]

  get "/directory/bootstrap/confirm" do
    token = params.get?(:token).to_s.strip

    if token.empty?
      html Portal::BootstrapResultPage, success: false, error_message: "Invalid registration link."
    else
      begin
        _customer_name, username = daemon.confirm_bootstrap(token)
        html Portal::BootstrapResultPage, success: true, username: username
      rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
        msg = case ex.status
              when 410 then "This registration link has already been used or has expired."
              when 404 then "Registration link is invalid."
              else          "Registration failed: #{ex.message}"
              end
        html Portal::BootstrapResultPage, success: false, error_message: msg
      end
    end
  end

  private def daemon
    Dirless::Ops::WebUI::DaemonClient.new
  end
end
