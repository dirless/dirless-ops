class Portal::Login < Lucky::Action
  accepted_formats [:html]

  get "/login" do
    html Portal::LoginPage, error: nil
  end
end
