abstract class PortalAction < Lucky::Action
  accepted_formats [:html]

  before require_portal_auth

  private def require_portal_auth
    if session.get?(:portal_email)
      continue
    else
      redirect to: Portal::Login
    end
  end

  private def portal_email : String
    session.get(:portal_email)
  end

  private def portal_customer_name : String
    session.get(:portal_customer_name)
  end

  private def portal_company : String
    session.get?(:portal_company) || ""
  end

  private def portal_provisioned : Bool
    session.get?(:portal_provisioned) == "true"
  end

  private def daemon : Dirless::Ops::WebUI::DaemonClient
    Dirless::Ops::WebUI::DaemonClient.new
  end
end
