require "./spec_helper"
require "../src/dirless/ops/poller"

private def purge!
  Dirless::Ops::Poller.new(3600).purge_unverified
end

private def surviving_names : Array(String)
  Dirless::Ops::Customer.all.map(&.name).sort!
end

private STALE = Time.utc - 3.hours
private FRESH = Time.utc - 10.minutes

describe "Poller#purge_unverified" do
  before_each { SpecHelper.clean_tables }

  it "purges a stale unverified free account" do
    SpecHelper.make_customer("bot-5004", "bot@spam.test", created_at: STALE)
    purge!
    surviving_names.should be_empty
  end

  it "keeps accounts younger than the TTL" do
    SpecHelper.make_customer("fresh-5005", "new@user.test", created_at: FRESH)
    purge!
    surviving_names.should eq ["fresh-5005"]
  end

  it "never touches verified accounts, no matter how old" do
    SpecHelper.make_customer("ok-5006", "ok@user.test", verified: true, created_at: STALE)
    purge!
    surviving_names.should eq ["ok-5006"]
  end

  it "never touches provisioned accounts even if unverified" do
    SpecHelper.make_customer("prov-5007", "p@user.test", provisioned: true, created_at: STALE)
    purge!
    surviving_names.should eq ["prov-5007"]
  end

  it "never touches paid/upgraded plans" do
    SpecHelper.make_customer("paid-5008", "g@user.test", plan: "growth", created_at: STALE)
    SpecHelper.make_customer("paid-5009", "s@user.test", plan: "scale", created_at: STALE)
    purge!
    surviving_names.should eq ["paid-5008", "paid-5009"]
  end

  it "purges stale accounts whose plan is explicitly free" do
    SpecHelper.make_customer("free-5010", "f@user.test", plan: "free", created_at: STALE)
    purge!
    surviving_names.should be_empty
  end

  it "never touches accounts with a Stripe customer (checkout started)" do
    SpecHelper.make_customer("strp-5011", "c@user.test", stripe_customer_id: "cus_123", created_at: STALE)
    purge!
    surviving_names.should eq ["strp-5011"]
  end

  it "deletes the purged account's provision jobs and nobody else's" do
    SpecHelper.make_customer("bot-5012", "b@spam.test", created_at: STALE)
    SpecHelper.make_customer("ok-5013", "ok2@user.test", verified: true, created_at: STALE)
    Dirless::Ops::ProvisionJob.new(customer_name: "bot-5012", status: "pending").save!
    Dirless::Ops::ProvisionJob.new(customer_name: "ok-5013", status: "pending").save!

    purge!

    jobs = Dirless::Ops::ProvisionJob.all.map(&.customer_name)
    jobs.should eq ["ok-5013"]
    surviving_names.should eq ["ok-5013"]
  end

  it "handles a mixed population correctly in one sweep" do
    SpecHelper.make_customer("bot-a-5014", "a@spam.test", created_at: STALE)
    SpecHelper.make_customer("bot-b-5015", "b2@spam.test", created_at: STALE)
    SpecHelper.make_customer("real-5016", "r@user.test", verified: true, provisioned: true, plan: "growth", stripe_customer_id: "cus_x", created_at: STALE)
    SpecHelper.make_customer("new-5017", "n@user.test", created_at: FRESH)

    purge!

    surviving_names.should eq ["new-5017", "real-5016"]
  end
end
