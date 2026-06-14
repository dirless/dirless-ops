# dirless-ops

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

Management plane for the Dirless platform. Exposes a JSON API (Grip) and a Lucky web UI across two domains:

- **admin.dirless.com** — Dirless employee admin UI. Login at `/admin-login`.
- **portal.dirless.com** — Customer self-service portal. Login at `/login`.

Both domains are served by the same binary on port 5001. Caddy enforces domain separation.

## Structure

| Directory | Purpose |
|-----------|---------|
| `src/` | Grip JSON API — customers, nodes, health checks, provision jobs, portal auth |
| `webui/` | Lucky web app served at the two domains above |

## Build & test

```sh
shards install
crystal spec
crystal build src/dirless_ops.cr        # API + deployer binary
crystal build webui/src/dirless_ops_webui.cr  # Lucky web UI binary
```

## Config

Set `DIRLESS_OPS_CONFIG` to override the config path (default: `/etc/dirless-ops/dirless-ops.toml`). See `config/dirless-ops.toml.example` for all options.

## Deployer mode

```sh
./dirless_ops --deploy   # claim and process one pending provision job, then exit
```

Used by a systemd timer on the ops machine to drain the provision job queue without a separate deployer process.

## API

All routes are under `/v1` and require `Authorization: Bearer <api_key>`:

| Method | Route | Description |
|--------|-------|-------------|
| `GET` | `/v1/health` | Unauthenticated health check |
| `GET\|POST` | `/v1/customers/` | List / create customers |
| `GET\|PATCH\|DELETE` | `/v1/customers/:name` | Get / update / delete a customer |
| `GET\|POST` | `/v1/nodes/` | List / create nodes |
| `GET\|PATCH\|DELETE` | `/v1/nodes/:name` | Get / update / delete a node |
| `GET` | `/v1/status` | Sync and agent status across all customers |
| `POST` | `/v1/portal/register` | Customer self-registration |
| `POST` | `/v1/portal/login` | Customer portal login |
| `GET\|POST` | `/v1/provision-jobs/` | List / create provision jobs |
| `GET\|PATCH` | `/v1/provision-jobs/:id` | Get / update a provision job |

## Deployment

Deploy via the `dirless-infra` Ansible playbooks:

```sh
# Full provision (requires KeePass)
ansible-playbook -i ansible/inventory/ops_hosts.yml ansible/ops-complete.yml

# Binary-only redeploy (no secrets needed)
ansible-playbook -i ansible/inventory/ops_hosts.yml ansible/ops-deploy-only.yml
```
