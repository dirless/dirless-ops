require "./granite_adapter_trashpanda"

module Dirless
  module Ops
    SCHEMA_STATEMENTS = [
      <<-SQL,
        CREATE TABLE IF NOT EXISTS customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          label TEXT,
          hmac_secret TEXT NOT NULL,
          aws_account_id TEXT,
          notes TEXT,
          created_at DATETIME,
          updated_at DATETIME
        )
      SQL
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_name ON customers (name)",
      <<-SQL,
        CREATE TABLE IF NOT EXISTS nodes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          ip TEXT NOT NULL,
          region TEXT NOT NULL,
          provider TEXT NOT NULL,
          is_primary INTEGER NOT NULL DEFAULT 0,
          created_at DATETIME,
          updated_at DATETIME
        )
      SQL
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_nodes_name ON nodes (name)",
      <<-SQL,
        CREATE TABLE IF NOT EXISTS health_checks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          node_id INTEGER NOT NULL,
          status TEXT NOT NULL,
          http_status INTEGER,
          response_time_ms INTEGER,
          tenant_count INTEGER,
          user_count INTEGER,
          error TEXT,
          checked_at DATETIME NOT NULL
        )
      SQL
      "CREATE INDEX IF NOT EXISTS idx_hc_customer_node ON health_checks (customer_id, node_id)",
      "CREATE INDEX IF NOT EXISTS idx_hc_checked_at ON health_checks (checked_at)",
      # Migrations: add columns added after initial deploy
      "ALTER TABLE health_checks ADD COLUMN tenant_count INTEGER",
      "ALTER TABLE health_checks ADD COLUMN user_count INTEGER",
      <<-SQL,
        CREATE TABLE IF NOT EXISTS customer_accounts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT NOT NULL,
          password_hash TEXT NOT NULL,
          customer_name TEXT NOT NULL,
          company TEXT,
          provisioned INTEGER NOT NULL DEFAULT 0,
          created_at DATETIME,
          updated_at DATETIME
        )
      SQL
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_accounts_email ON customer_accounts (email)",
      <<-SQL,
        CREATE TABLE IF NOT EXISTS provision_jobs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_name TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          error TEXT,
          created_at DATETIME,
          started_at DATETIME,
          completed_at DATETIME
        )
      SQL
      "CREATE INDEX IF NOT EXISTS idx_provision_jobs_status ON provision_jobs (status)",
      "CREATE INDEX IF NOT EXISTS idx_provision_jobs_customer ON provision_jobs (customer_name)",
      # Migration: first name, last name, country on customer accounts
      "ALTER TABLE customer_accounts ADD COLUMN first_name TEXT",
      "ALTER TABLE customer_accounts ADD COLUMN last_name TEXT",
      "ALTER TABLE customer_accounts ADD COLUMN country TEXT",
      # Migration: replication lag tracking
      "ALTER TABLE health_checks ADD COLUMN data_updated_at DATETIME",
      # Migration: agent heartbeat tracking
      "ALTER TABLE health_checks ADD COLUMN active_agents INTEGER",
      "ALTER TABLE health_checks ADD COLUMN agents_json TEXT",
      # Migration: node prober resource columns (cpu, memory, disk, load, probe timestamp)
      # NOTE: these were applied directly to ops.db before being captured in code.
      "ALTER TABLE nodes ADD COLUMN cpu_count INTEGER",
      "ALTER TABLE nodes ADD COLUMN memory_gb INTEGER",
      "ALTER TABLE nodes ADD COLUMN free_memory_mb INTEGER",
      "ALTER TABLE nodes ADD COLUMN free_disk_gb INTEGER",
      "ALTER TABLE nodes ADD COLUMN load_5m REAL",
      "ALTER TABLE nodes ADD COLUMN last_probed_at DATETIME",
      "ALTER TABLE nodes ADD COLUMN probe_error TEXT",
      # Migration: per-node backend service states from node prober
      "ALTER TABLE nodes ADD COLUMN services_json TEXT",
      # Migration: Stripe integration
      "ALTER TABLE customer_accounts ADD COLUMN stripe_customer_id TEXT",
      "ALTER TABLE customer_accounts ADD COLUMN beta_customer INTEGER NOT NULL DEFAULT 0",
      "UPDATE customer_accounts SET beta_customer = 0 WHERE beta_customer IS NULL",
      "ALTER TABLE customer_accounts ADD COLUMN plan TEXT",
      # Migration: Syncthing folder completion per node
      "ALTER TABLE nodes ADD COLUMN syncthing_status_json TEXT",
      # Migration: consecutive probe failure counter for alerting
      "ALTER TABLE nodes ADD COLUMN probe_failure_count INTEGER NOT NULL DEFAULT 0",
      # Migration: email verification
      # DEFAULT 1 so that all existing accounts are automatically considered verified.
      # New registrations set email_verified = 0 explicitly and go through the flow.
      "ALTER TABLE customer_accounts ADD COLUMN email_verified INTEGER NOT NULL DEFAULT 1",
      "ALTER TABLE customer_accounts ADD COLUMN email_verify_token TEXT",
      # Migration: explicit tenant_id for non-AWS customers (AWS customers derive it at runtime).
      "ALTER TABLE customers ADD COLUMN tenant_id TEXT",
      # Migration: merge customer_accounts into customers (2026-05-25)
      "ALTER TABLE customers ADD COLUMN email TEXT",
      "ALTER TABLE customers ADD COLUMN password_hash TEXT",
      "ALTER TABLE customers ADD COLUMN first_name TEXT",
      "ALTER TABLE customers ADD COLUMN last_name TEXT",
      "ALTER TABLE customers ADD COLUMN company TEXT",
      "ALTER TABLE customers ADD COLUMN country TEXT",
      # DEFAULT 1 so admin-created customers are treated as verified (no email flow).
      # New portal registrations always set email_verified = 0 explicitly.
      "ALTER TABLE customers ADD COLUMN email_verified INTEGER NOT NULL DEFAULT 1",
      "ALTER TABLE customers ADD COLUMN email_verify_token TEXT",
      "ALTER TABLE customers ADD COLUMN provisioned INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE customers ADD COLUMN stripe_customer_id TEXT",
      "ALTER TABLE customers ADD COLUMN beta_customer INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE customers ADD COLUMN plan TEXT",
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_email ON customers (email)",
      # Backfill account data from customer_accounts into customers.
      # Uses correlated subqueries; silently skipped if customer_accounts doesn't exist.
      "UPDATE customers SET " \
      "email = (SELECT email FROM customer_accounts WHERE customer_name = customers.name), " \
      "password_hash = (SELECT password_hash FROM customer_accounts WHERE customer_name = customers.name), " \
      "first_name = (SELECT first_name FROM customer_accounts WHERE customer_name = customers.name), " \
      "last_name = (SELECT last_name FROM customer_accounts WHERE customer_name = customers.name), " \
      "company = (SELECT company FROM customer_accounts WHERE customer_name = customers.name), " \
      "country = (SELECT country FROM customer_accounts WHERE customer_name = customers.name), " \
      "provisioned = (SELECT provisioned FROM customer_accounts WHERE customer_name = customers.name), " \
      "email_verified = (SELECT email_verified FROM customer_accounts WHERE customer_name = customers.name), " \
      "email_verify_token = (SELECT email_verify_token FROM customer_accounts WHERE customer_name = customers.name), " \
      "stripe_customer_id = (SELECT stripe_customer_id FROM customer_accounts WHERE customer_name = customers.name), " \
      "beta_customer = (SELECT beta_customer FROM customer_accounts WHERE customer_name = customers.name), " \
      "plan = (SELECT plan FROM customer_accounts WHERE customer_name = customers.name) " \
      "WHERE EXISTS (SELECT 1 FROM customer_accounts WHERE customer_name = customers.name)",
      # Backfill company from legacy label column for admin-created customers.
      "UPDATE customers SET company = label WHERE company IS NULL AND label IS NOT NULL",
      # Migration: track how many times a provision job has been auto-reset due to timeout.
      "ALTER TABLE provision_jobs ADD COLUMN reset_count INTEGER",
      # Migration: per-customer server limit (derived from plan, admin-overridable).
      "ALTER TABLE customers ADD COLUMN server_limit INTEGER",
      # Migration: per-customer SSH CA keypair and cert TTL for dirless-connect.
      "ALTER TABLE customers ADD COLUMN ca_private_key TEXT",
      "ALTER TABLE customers ADD COLUMN ca_public_key TEXT",
      "ALTER TABLE customers ADD COLUMN cert_ttl_seconds INTEGER",
      # SSH CA: one-time bootstrap tokens (magic link email flow).
      <<-SQL,
        CREATE TABLE IF NOT EXISTS ssh_bootstrap_tokens (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          token TEXT NOT NULL,
          customer_name TEXT NOT NULL,
          username TEXT NOT NULL,
          email TEXT NOT NULL,
          age_public_key TEXT NOT NULL,
          ssh_public_key TEXT NOT NULL,
          used INTEGER NOT NULL DEFAULT 0,
          expires_at DATETIME NOT NULL,
          created_at DATETIME,
          updated_at DATETIME
        )
      SQL
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_ssh_bootstrap_token ON ssh_bootstrap_tokens (token)",
      "CREATE INDEX IF NOT EXISTS idx_ssh_bootstrap_customer ON ssh_bootstrap_tokens (customer_name)",
      # SSH CA: registered user keypairs (age public key + SSH public key per user).
      <<-SQL,
        CREATE TABLE IF NOT EXISTS ssh_user_registrations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_name TEXT NOT NULL,
          username TEXT NOT NULL,
          email TEXT NOT NULL,
          age_public_key TEXT NOT NULL,
          ssh_public_key TEXT NOT NULL,
          created_at DATETIME,
          updated_at DATETIME
        )
      SQL
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_ssh_user_reg ON ssh_user_registrations (customer_name, username)",
      # SSH CA: in-flight age challenges (nonce encrypted to user, 60s expiry).
      # nonce_hash = SHA256(nonce_plaintext) — plaintext is never persisted so a
      # DB dump cannot be used to mint certificates without the user's age private key.
      <<-SQL,
        CREATE TABLE IF NOT EXISTS ssh_challenges (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_name TEXT NOT NULL,
          username TEXT NOT NULL,
          nonce_hash TEXT NOT NULL,
          expires_at DATETIME NOT NULL,
          created_at DATETIME,
          updated_at DATETIME
        )
      SQL
      "CREATE INDEX IF NOT EXISTS idx_ssh_challenges_user ON ssh_challenges (customer_name, username)",
    ]

    def self.setup_db(database_path : String)
      Dir.mkdir_p(File.dirname(database_path))

      Granite::Connections << Granite::Adapter::Trashpanda.new(
        name: "sqlite",
        url: "trashpanda:#{database_path}"
      )

      db = Granite::Connections["sqlite"].not_nil![:writer].database

      # Self-heal corrupted nodes table. The TPDB v0.8.6 leaf-page-bloat bug
      # could corrupt row data after DELETE+INSERT cycles. If reading any row
      # raises ColumnTypeMismatchError, drop the table so SCHEMA_STATEMENTS
      # can recreate it cleanly. Node data is repopulated by register-ops.yml.
      begin
        db.query("SELECT name FROM nodes") { |rs| rs.each { rs.read(String) } }
      rescue DB::ColumnTypeMismatchError
        Log.warn { "nodes table has corrupted rows - dropping and recreating (TPDB leaf-page-bloat repair)" }
        db.exec("DROP TABLE IF EXISTS nodes")
      rescue DB::Error
        # Table doesn't exist yet - SCHEMA_STATEMENTS will create it.
      end

      SCHEMA_STATEMENTS.each do |sql|
        db.exec(sql)
      rescue ex : Exception
        msg = ex.message || ""
        if msg.includes?("duplicate column") || msg.includes?("already exists")
          Log.debug { "schema statement skipped (idempotent): #{msg}" }
        else
          Log.warn { "schema migration failed: #{msg} - SQL: #{sql.strip[0, 80]}" }
        end
      end
    end
  end
end
