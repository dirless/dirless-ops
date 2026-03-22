class Auth::Create < Lucky::Action
  default_format :html
  accepted_formats [:html]

  post "/login" do
    username = params.get?(:username).to_s.strip
    password = params.get?(:password).to_s

    if Dirless::Ops::WebUI::Auth.valid?(username, password)
      session.set(:authenticated, "true")
      redirect to: Home::Index
    else
      html LoginPage, error: "Invalid username or password."
    end
  end
end
