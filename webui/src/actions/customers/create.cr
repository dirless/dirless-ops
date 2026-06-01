class Customers::Create < BrowserAction
  post "/customers" do
    body = {} of String => String
    body["name"] = params.get(:name)
    body["hmac_secret"] = params.get(:hmac_secret)
    params.get?(:email).try { |v| body["email"] = v unless v.empty? }
    params.get?(:company).try { |v| body["company"] = v unless v.empty? }
    params.get?(:aws_account_id).try { |v| body["aws_account_id"] = v unless v.empty? }
    params.get?(:notes).try { |v| body["notes"] = v unless v.empty? }

    errors = {} of String => String
    errors["email"] = "Please enter an email address" if body["email"]?.nil?

    if errors.empty?
      begin
        customer = daemon.create_customer(body)
        flash.success = "Customer #{customer.name} created"
        redirect to: Customers::Show.with(name: customer.name)
      rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
        html Customers::NewPage, errors: ex.fields, values: body
      end
    else
      html Customers::NewPage, errors: errors, values: body
    end
  end
end
