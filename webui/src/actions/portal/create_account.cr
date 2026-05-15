class Portal::CreateAccount < Lucky::Action
  accepted_formats [:html]

  PAID_PLANS = {"starter", "growth", "scale"}

  post "/register" do
    email      = params.get?(:email).to_s.strip
    password   = params.get?(:password).to_s
    confirm    = params.get?(:confirm_password).to_s
    first_name = params.get?(:first_name).to_s.strip
    last_name  = params.get?(:last_name).to_s.strip
    company    = params.get?(:company).to_s.strip
    country    = params.get?(:country).to_s.strip
    plan       = params.get?(:plan).to_s.strip.downcase
    plan       = "beta" unless {"beta", "starter", "growth", "scale"}.includes?(plan)

    errors = {} of String => String
    values = {"email" => email, "first_name" => first_name, "last_name" => last_name, "company" => company, "country" => country, "plan" => plan}

    errors["email"]            = "Required"                       if email.empty?
    errors["email"]            = "Invalid email"                  unless email.includes?("@")
    errors["password"]         = "Required"                       if password.empty?
    errors["password"]         = "Must be at least 12 characters" if password.size < 12
    errors["confirm_password"] = "Passwords do not match"         if password != confirm
    errors["first_name"]       = "Required"                       if first_name.empty?
    errors["last_name"]        = "Required"                       if last_name.empty?
    errors["company"]          = "Required"                       if company.empty?
    errors["country"]          = "Required"                       if country.empty?

    unless errors.empty?
      return html Portal::RegisterPage, errors: errors, values: values
    end

    begin
      account = daemon.portal_register(email, password, first_name, last_name, company, country)

      if PAID_PLANS.includes?(plan)
        proto = request.headers["X-Forwarded-Proto"]? || "https"
        host  = request.headers["Host"]
        success_url = "#{proto}://#{host}/payment-success?session_id={CHECKOUT_SESSION_ID}"
        cancel_url  = "#{proto}://#{host}/register"
        checkout_url = daemon.create_checkout_session(account.customer_name, plan, success_url, cancel_url)
        redirect to: checkout_url
      else
        session.set(:portal_email, account.email)
        session.set(:portal_customer_name, account.customer_name)
        session.set(:portal_company, account.company || "")
        session.set(:portal_provisioned, account.provisioned.to_s)
        redirect to: Portal::Dashboard
      end
    rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
      errors = ex.fields.empty? ? {"_base" => ex.message.to_s} : ex.fields
      html Portal::RegisterPage, errors: errors, values: values
    end
  end

  private def daemon
    Dirless::Ops::WebUI::DaemonClient.new
  end
end
