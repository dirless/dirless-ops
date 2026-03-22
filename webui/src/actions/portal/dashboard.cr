class Portal::Dashboard < PortalAction
  get "/portal/dashboard" do
    customer_info = begin
      daemon.customer(portal_customer_name)
    rescue
      nil
    end

    customer_status = begin
      daemon.customer_status(portal_customer_name)
    rescue
      nil
    end

    html Portal::DashboardPage,
      email: portal_email,
      company: portal_company,
      customer_name: portal_customer_name,
      provisioned: portal_provisioned,
      customer_info: customer_info,
      customer_status: customer_status
  end
end
