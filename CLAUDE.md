# dirless-ops

Crystal management plane for the Dirless platform. Exposes a JSON API (Grip) and a Lucky web UI split across two domains:

- **admin.dirless.com** — Dirless employee admin UI. Login at `/admin-login`.
- **portal.dirless.com** — Customer self-service portal. Login at `/login`.

Both domains are served by the same `dirless-ops-webui` binary on port 5001. Caddy enforces domain separation (admin routes blocked on portal domain and vice versa).

## Structure

This repo contains three sub-projects:

| Directory | Purpose |
|-----------|---------|
| `src/` | Grip JSON API — customers, nodes, health checks, provision jobs, portal auth. The internal backend. |
| `webui/` | Lucky web app — what users see at **management.dirless.com**. Talks to the Grip API via `daemon_client.cr`. |
| `cli/` | `dirless-ops-cli` — command-line client for the ops API |

## Language / stack

- Crystal
- [Grip](https://github.com/grip-framework/grip) HTTP framework (API server)
- [Lucky](https://luckyframework.org/) web framework (web UI)
- Granite ORM (SQLite)
- TOML config

## Key entry points

| File | Purpose |
|------|---------|
| `src/dirless_ops.cr` | Entry point — loads config, starts poller, runs Grip server (or deployer with `--deploy`) |
| `src/dirless/ops/models/` | Granite models: Customer, Node, HealthCheck, CustomerAccount, ProvisionJob |
| `src/dirless/ops/routes/` | Controllers: customers, nodes, status, portal, provision jobs |
| `src/dirless/ops/middleware/api_key.cr` | API key authentication middleware |
| `src/dirless/ops/poller.cr` | Background poller (health checks, sync status) |
| `src/dirless/ops/deployer.cr` | Provisioning job runner (same logic as `dirless-deployer`) |
| `config/dirless-ops.toml.example` | Config reference |

## API routes (all under `/v1`, API key auth required)

- `GET /v1/health`
- `GET|POST /v1/customers/`, `GET|PATCH|DELETE /v1/customers/:name`
- `GET|POST /v1/nodes/`, `GET|PATCH|DELETE /v1/nodes/:name`
- `GET /v1/status`
- `POST /v1/portal/register`, `POST /v1/portal/login`
- `GET /v1/provision-jobs/`, `GET|PATCH /v1/provision-jobs/:id`

## Config

Override path with `DIRLESS_OPS_CONFIG` env var (default: `/etc/dirless-ops/dirless-ops.toml`). Set `DIRLESS_OPS_ENV` for environment name (default: `PRODUCTION`).

## Build & test

```sh
shards install
bin/ameba src/      # lint
crystal spec
crystal build src/dirless_ops.cr
```

## Deployer mode

```sh
./dirless_ops --deploy   # claim and process one pending provision job, then exit
```

Used by a systemd timer to drain the provision job queue.

## Outgoing email (notification system — Crystal side pending)

Transactional email is sent via a filesystem spool on the ops machine. To send an email from Crystal code, write an RFC 2822 `.eml` file atomically to `/var/spool/dirless-ops/outbox/`:

```crystal
# Write to a .tmp file first, then rename for atomicity
tmp = "/var/spool/dirless-ops/outbox/#{Random::Secure.hex(8)}.eml.tmp"
final = tmp.sub(".eml.tmp", ".eml")
File.write(tmp, <<-EML)
  From: Dirless <info@dirless.com>
  To: #{email}
  Subject: Welcome to Dirless

  Hello, ...
  EML
File.rename(tmp, final)
```

A systemd timer (`dirless-flush-mail.timer`, every 1s) picks up `.eml` files and delivers them via msmtp. The `Notifier` class lives at `src/dirless/ops/notifier.cr` and is fully implemented.

**Notifier methods:**
- `welcome(email, company, customer_name)` — fired in `portal.cr` after registration commits
- `environment_ready(email, company, customer_name)` — fired in `deployer.cr` after successful provision
- `provisioning_failed(email, company)` — fired in `deployer.cr` on Ansible failure/timeout
- `account_deleted(email, company)` — fired in `customers.cr` after admin deletes a customer

**Config** (optional `[notifications]` section in `dirless-ops.toml`):
- `mail_spool_dir` — defaults to `/var/spool/dirless-ops/outbox`

## Lucky session cookie gotcha

Never put login routes under a nested path (e.g. `/admin/login`). Lucky does not set `Path=/` on session cookies, so the browser scopes the cookie to the URL's directory. Sessions break silently — the login POST succeeds but the next request sees an empty session.

Always use flat root-level paths for login routes: `/admin-login`, `/login`, etc.
