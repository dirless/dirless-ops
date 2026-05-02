class Auth::Login < Lucky::Action
  default_format :html
  accepted_formats [:html]

  get "/admin-login" do
    if session.get?(:authenticated) == "true"
      redirect to: Home::Index
    else
      html LoginPage, error: nil
    end
  end
end
