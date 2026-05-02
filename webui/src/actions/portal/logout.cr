class Portal::Logout < Lucky::Action
  accepted_formats [:html]

  post "/logout" do
    session.delete(:portal_email)
    session.delete(:portal_customer_name)
    session.delete(:portal_company)
    session.delete(:portal_provisioned)
    redirect to: Portal::Login
  end
end
