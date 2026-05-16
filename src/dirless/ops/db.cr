require "granite/adapter/sqlite"
require "sqlite3"

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
    ]

    def self.setup_db(database_path : String)
      Dir.mkdir_p(File.dirname(database_path))

      Granite::Connections << Granite::Adapter::Sqlite.new(
        name: "sqlite",
        url: "sqlite3://#{database_path}"
      )

      db = Granite::Connections["sqlite"].not_nil![:writer].database
      SCHEMA_STATEMENTS.each do |sql|
        db.exec(sql)
      rescue ex : Exception
        msg = ex.message || ""
        if msg.includes?("duplicate column") || msg.includes?("already exists")
          Log.debug { "schema statement skipped (idempotent): #{msg}" }
        else
          Log.warn { "schema migration failed: #{msg} — SQL: #{sql.strip[0, 80]}" }
        end
      end
    end
  end
end
