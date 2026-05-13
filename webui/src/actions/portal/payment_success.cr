class Portal::PaymentSuccess < Lucky::Action
  accepted_formats [:html]

  get "/payment/success" do
    session_id = params.get?(:session_id).to_s.strip

    if session_id.empty?
      return redirect to: Portal::Register
    end

    begin
      account = daemon.verify_checkout_session(session_id)
      session.set(:portal_email, account.email)
      session.set(:portal_customer_name, account.customer_name)
      session.set(:portal_company, account.company || "")
      session.set(:portal_provisioned, account.provisioned.to_s)
      redirect to: Portal::Dashboard
    rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
      redirect to: Portal::Register
    end
  end

  private def daemon
    Dirless::Ops::WebUI::DaemonClient.new
  end
end
