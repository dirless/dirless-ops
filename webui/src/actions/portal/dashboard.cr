class Portal::Dashboard < PortalAction
  get "/dashboard" do
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

    # Check live provisioned status instead of stale session value.
    # A completed provision job means the customer is ready.
    provisioned = if portal_provisioned
                    true
                  else
                    jobs = daemon.provision_jobs
                    jobs.any? { |j| j.customer_name == portal_customer_name && j.status == "completed" }
                  end

    # Update session so subsequent page loads skip the API call
    session.set(:portal_provisioned, "true") if provisioned

    html Portal::DashboardPage,
      email: portal_email,
      company: portal_company,
      customer_name: portal_customer_name,
      provisioned: provisioned,
      customer_info: customer_info,
      customer_status: customer_status
  end
end
