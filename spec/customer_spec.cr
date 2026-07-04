require "./spec_helper"

describe "Customer.limit_for_plan" do
  it "maps every plan to its server limit" do
    Dirless::Ops::Customer.limit_for_plan("free").should eq 10
    Dirless::Ops::Customer.limit_for_plan("growth").should eq 50
    Dirless::Ops::Customer.limit_for_plan("scale").should eq 200
  end

  it "falls back to the free limit for nil or unknown plans" do
    Dirless::Ops::Customer.limit_for_plan(nil).should eq 10
    Dirless::Ops::Customer.limit_for_plan("enterprise-custom").should eq 10
  end
end
