#!/usr/bin/env crystal
# One-shot migration: copies customer_accounts rows into the customers table.
#
# Run this ONCE after upgrading to the version that merged the two tables.
# Safe to re-run: it skips customers that already have an email set.
#
# Usage:
#   ./dirless-ops-migrate [--config /path/to/dirless-ops.toml]

require "./dirless/ops/config"
require "./dirless/ops/db"
require "./dirless/ops/models/customer"

config_path = if idx = ARGV.index("--config")
                ARGV[idx + 1]
              else
                ENV.fetch("DIRLESS_OPS_CONFIG", "/etc/dirless-ops/dirless-ops.toml")
              end

puts "Loading config from #{config_path}"
config = Dirless::Ops::Config.load(config_path)
Dirless::Ops.setup_db(config.database_path)

db = Granite::Connections["sqlite"].not_nil![:writer].database

puts "Checking for un-migrated customer_accounts rows..."

# Read all customer_accounts rows
rows = db.query_all(
  "SELECT customer_name, email, password_hash, first_name, last_name, company, country, " \
  "provisioned, email_verified, email_verify_token, stripe_customer_id, beta_customer, plan " \
  "FROM customer_accounts",
  as: {String, String, String, String?, String?, String?, String?, Int32, Int32, String?, String?, Int32, String?}
) rescue begin
  puts "customer_accounts table not found or empty - nothing to migrate."
  exit 0
end

if rows.empty?
  puts "No rows in customer_accounts - nothing to migrate."
  exit 0
end

puts "Found #{rows.size} account row(s) to migrate."
migrated = 0
skipped = 0

rows.each do |customer_name, email, password_hash, first_name, last_name, company, country, provisioned, email_verified, email_verify_token, stripe_customer_id, beta_customer, plan|
  # Skip if already migrated (email already set on the customers row)
  existing_email = db.scalar("SELECT email FROM customers WHERE name = ?", customer_name) rescue nil
  if existing_email && !existing_email.to_s.empty?
    puts "  SKIP #{customer_name} (already has email: #{existing_email})"
    skipped += 1
    next
  end

  result = db.exec(
    "UPDATE customers SET email = ?, password_hash = ?, first_name = ?, last_name = ?, " \
    "company = ?, country = ?, provisioned = ?, email_verified = ?, email_verify_token = ?, " \
    "stripe_customer_id = ?, beta_customer = ?, plan = ? WHERE name = ?",
    email, password_hash, first_name, last_name, company, country,
    provisioned, email_verified, email_verify_token, stripe_customer_id, beta_customer, plan,
    customer_name
  )

  if result.rows_affected > 0
    puts "  MIGRATED #{customer_name} → #{email}"
    migrated += 1
  else
    puts "  WARNING: customer '#{customer_name}' not found in customers table (orphaned account?)"
  end
end

puts ""
puts "Done. Migrated: #{migrated}, Skipped (already done): #{skipped}"
