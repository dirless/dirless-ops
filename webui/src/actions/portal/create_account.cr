class Portal::CreateAccount < Lucky::Action
  accepted_formats [:html]

  post "/register" do
    email    = params.get?(:email).to_s.strip
    password = params.get?(:password).to_s
    confirm  = params.get?(:confirm_password).to_s
    company  = params.get?(:company).to_s.strip

    errors = {} of String => String
    values = {"email" => email, "company" => company}

    errors["email"]            = "Required"                       if email.empty?
    errors["email"]            = "Invalid email"                  unless email.includes?("@")
    errors["password"]         = "Required"                       if password.empty?
    errors["password"]         = "Must be at least 12 characters" if password.size < 12
    errors["confirm_password"] = "Passwords do not match"         if password != confirm
    errors["company"]          = "Required"                       if company.empty?

    unless errors.empty?
      return html Portal::RegisterPage, errors: errors, values: values
    end

    begin
      account = daemon.portal_register(email, password, company)
      session.set(:portal_email, account.email)
      session.set(:portal_customer_name, account.customer_name)
      session.set(:portal_company, account.company || "")
      session.set(:portal_provisioned, account.provisioned.to_s)
      redirect to: Portal::Dashboard
    rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
      errors = ex.fields.empty? ? {"_base" => ex.message.to_s} : ex.fields
      html Portal::RegisterPage, errors: errors, values: values
    end
  end

  private def daemon
    Dirless::Ops::WebUI::DaemonClient.new
  end
end
