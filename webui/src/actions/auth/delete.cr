class Auth::Delete < Lucky::Action
  default_format :html
  accepted_formats [:html]

  delete "/logout" do
    session.clear
    redirect to: Auth::Login
  end
end
