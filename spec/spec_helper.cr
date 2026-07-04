require "spec"
require "file_utils"

# Granite's `connection` macro validates the connection at class-load time,
# so the test database must be registered BEFORE any model is required -
# same ordering rule as src/dirless_ops.cr.
require "../src/dirless/ops/db"

SPEC_DB_DIR = File.join(Dir.tempdir, "dirless-ops-spec-#{Random::Secure.hex(4)}")
Dirless::Ops.setup_db(File.join(SPEC_DB_DIR, "test.db"))

require "../src/dirless/ops/models/customer"
require "../src/dirless/ops/models/node"
require "../src/dirless/ops/models/health_check"
require "../src/dirless/ops/models/provision_job"

Spec.after_suite do
  FileUtils.rm_rf(SPEC_DB_DIR)
end

module SpecHelper
  # Wipe rows between examples so specs stay independent.
  def self.clean_tables
    Dirless::Ops::Customer.clear
    Dirless::Ops::ProvisionJob.clear
  end

  def self.make_customer(name : String,
                         email : String,
                         verified : Bool = false,
                         provisioned : Bool = false,
                         plan : String? = nil,
                         stripe_customer_id : String? = nil,
                         created_at : Time = Time.utc) : Dirless::Ops::Customer
    customer = Dirless::Ops::Customer.new(
      name: name,
      hmac_secret: Random::Secure.hex(8),
      tenant_id: Random::Secure.hex(8),
      cloud_provider: "dirless",
      email: email,
      email_verified: verified,
      provisioned: provisioned,
      plan: plan,
      stripe_customer_id: stripe_customer_id,
      beta_customer: false,
    )
    customer.save!
    # Granite's timestamps macro owns created_at (set on create, never on
    # update), so backdating for purge-window tests must go through SQL.
    db = Granite::Connections["sqlite"].not_nil![:writer].database
    db.exec("UPDATE customers SET created_at = ? WHERE name = ?", created_at, name)
    Dirless::Ops::Customer.find_by!(name: name)
  end
end
