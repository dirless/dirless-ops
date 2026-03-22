class Portal::CreateSession < Lucky::Action
  accepted_formats [:html]

  post "/portal/login" do
    email    = params.get?(:email).to_s.strip
    password = params.get?(:password).to_s

    begin
      account = daemon.portal_login(email, password)
      session.set(:portal_email, account.email)
      session.set(:portal_customer_name, account.customer_name)
      session.set(:portal_company, account.company || "")
      session.set(:portal_provisioned, account.provisioned.to_s)
      redirect to: Portal::Dashboard
    rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
      html Portal::LoginPage, error: "Invalid email or password"
    end
  end

  private def daemon
    Dirless::Ops::WebUI::DaemonClient.new
  end
end
