class Customers::Create < BrowserAction
  post "/customers" do
    body = {} of String => String
    body["name"] = params.get(:name)
    body["hmac_secret"] = params.get(:hmac_secret)
    params.get?(:label).try { |v| body["label"] = v unless v.empty? }
    params.get?(:aws_account_id).try { |v| body["aws_account_id"] = v unless v.empty? }
    params.get?(:notes).try { |v| body["notes"] = v unless v.empty? }

    begin
      customer = daemon.create_customer(body)
      flash.success = "Customer #{customer.name} created"
      redirect to: Customers::Show.with(name: customer.name)
    rescue ex : Dirless::Ops::WebUI::DaemonClient::Error
      html Customers::NewPage, errors: ex.fields, values: body
    end
  end
end
