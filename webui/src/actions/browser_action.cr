require "../dirless/ops/webui/daemon_client"

abstract class BrowserAction < Lucky::Action
  accepted_formats [:html]

  before require_auth

  private def require_auth
    if session.get?(:authenticated) == "true"
      continue
    else
      redirect to: Auth::Login
    end
  end

  private def daemon : Dirless::Ops::WebUI::DaemonClient
    Dirless::Ops::WebUI::DaemonClient.new
  end
end
