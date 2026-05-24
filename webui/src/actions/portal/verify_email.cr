class Portal::VerifyEmail < Lucky::Action
  accepted_formats [:html]

  get "/verify-email" do
    token = params.get?(:token).to_s.strip

    if token.empty?
      flash.failure = "Invalid verification link."
      redirect to: Portal::Login
    end

    begin
      account = daemon.verify_email(token)
      session.set(:portal_email_verified, "true") if session.get?(:portal_email) == account.email
      flash.success = "Email verified! Your environment is being set up."
      redirect to: Portal::Login
    rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
      flash.failure = "Verification link is invalid or has already been used."
      redirect to: Portal::Login
    end
  end

  private def daemon
    Dirless::Ops::WebUI::DaemonClient.new
  end
end
