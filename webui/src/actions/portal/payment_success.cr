class Portal::PaymentSuccess < Lucky::Action
  accepted_formats [:html]

  get "/payment-success" do
    session_id = params.get?(:session_id).to_s.strip

    if session_id.empty?
      flash.failure = "Missing payment session. Please try again."
      return redirect to: Portal::Register
    end

    begin
      account = daemon.verify_checkout_session(session_id)
      session.set(:portal_email, account.email)
      session.set(:portal_customer_name, account.customer_name)
      session.set(:portal_company, account.company || "")
      session.set(:portal_provisioned, account.provisioned.to_s)
      flash.success = "Payment confirmed! Welcome to Dirless."
      redirect to: Portal::Dashboard
    rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
      flash.failure = "We couldn't confirm your payment. Please contact support."
      redirect to: Portal::Register
    end
  end

  private def daemon
    Dirless::Ops::WebUI::DaemonClient.new
  end
end
