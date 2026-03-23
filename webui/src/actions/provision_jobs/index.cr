class ProvisionJobs::Index < BrowserAction
  get "/provision-jobs" do
    jobs = daemon.provision_jobs
    html ProvisionJobs::IndexPage, jobs: jobs
  end
end
