class Portal::ResendVerification < PortalAction
  accepted_formats [:html]

  post "/resend-verification" do
    begin
      daemon.resend_verification(portal_customer_name)
      flash.success = "Verification email sent — please check your inbox."
    rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
      if ex.status == 429
        flash.failure = "Please wait a moment before requesting another verification email."
      else
        flash.failure = "Could not send verification email. Please try again."
      end
    end
    redirect to: Portal::Dashboard
  end
end
