# Dirless: Local User Preservation (Two-Blob Architecture)

## Goal

Allow portal users to add local directory users that survive syncer cycles. Currently the
syncer overwrites the snapshot every ~60 seconds with IAM Identity Center data, deleting
any locally-added users.

## Background / Constraints

- **Zero-knowledge backend**: the backend stores opaque encrypted ciphertext. It never sees
  plaintext user data.
- **One age keypair**: a single age keypair is used for all encryption. No second key is
  introduced. The public key is stored in the backend (non-secret). The private key lives on
  the agent machine and is held in-session by the portal user when they need to decrypt.
- **Syncer is unchanged**: the syncer continues writing its snapshot exactly as it does today.
  It is not aware of local users.

---

## Architecture: Two Blobs

Two separate encrypted blobs are stored per tenant in the backend:

| | Syncer blob | Local blob |
|---|---|---|
| Written by | `dirless-syncer` | Portal (dirless-ops webui) |
| Content | IAM Identity Center users + groups | Manually added users + groups |
| Encrypted with | Age public key | Age public key |
| Mutated by portal? | No (read-only) | Yes (full CRUD) |
| Endpoint | `PUT /snapshot/aws-identity-center` (renamed) | `PUT /snapshot/local` (new) |

The **agent** fetches both blobs, decrypts both with the same private key, merges them, and
serves the result via NSS.

**Merge rule**: union of all blobs. On username collision, **local blob wins** over any cloud
source. Rationale: a manually-added user represents deliberate intent; silently overriding it
with a cloud-sourced entry would be more surprising than the reverse. The duplicate warning
system (email + portal banner) ensures the admin is aware of the conflict and can consciously
resolve it by deleting the local entry if they want the cloud version to take over.

Cloud-vs-cloud tie-breaking (future, when multiple cloud sources are active) is left to be
defined when that feature is implemented.

---

## Age Key Lifecycle

### First-time setup (no syncer)

1. Portal shows a "Set up your directory key" page when no public key is on record.
2. User chooses one of:
   - **Paste your own**: user provides an existing age private key (portal derives public key from it).
   - **Generate for me**: portal generates an age keypair, displays the private key for
     one-time download, stores the public key in the backend.
3. The private key is **never stored server-side**. After leaving the setup page it is gone.
   If lost: the user must reset the DB (wipe both blobs, start over).
4. The public key is stored in the backend and used by the portal to encrypt the local blob.

### When syncer is already set up

The syncer submits its public key during enrollment. That becomes the canonical key.
The portal retrieves it from the backend. No conflict — one key, always.

### Agent setup

The age private key must be present at `age_key_path` (configurable in agent TOML, e.g.
`/etc/dirless/agent-age.key`). This is deployed via Ansible (ops-complete.yml or
ops-deploy-only.yml). The agent uses it to decrypt both blobs.

---

## Duplicate Handling

### At write time (portal adding a local user)

1. The portal user has provided their age private key for the session (existing UX).
2. Portal decrypts **both blobs** using that key.
3. Portal builds the merged username set.
4. If the username already exists in either blob → **block the add**, show an error:
   `"User 'goatman' already exists in your directory."`

### After the fact (IAM IC later adds a user that exists in the local blob)

1. Agent detects a collision at merge time (same username in both blobs).
2. Agent applies the merge rule (syncer blob wins — IAM IC user takes effect).
3. Agent records the collision in its local DB.
4. Agent triggers an **email notification** to the customer (via ops API):
   `"X duplicate user(s) found in your directory. IAM Identity Center users take precedence.
   Please log in to the portal to review and clean up your local user list."`
5. The **portal** shows a persistent banner when there are known duplicates:
   `"⚠ X users in your local directory are duplicated by IAM Identity Center users.
   Decrypt with your age key to see the list."`

Email is sent **at most once per sync cycle per tenant** (not on every agent tick).

---

## Components to Change

### 1. Backend (`dirless-backend`) — smallest blast radius, do first

**New field on the tenant/snapshot record**: `local_snapshot TEXT` (nullable).

New and renamed API endpoints (authenticated with HMAC, same as existing snapshot endpoints):

```
GET  /snapshot/aws-identity-center   → returns { "snapshot": "<base64 ciphertext or null>" }
PUT  /snapshot/aws-identity-center   → body: { "snapshot": "<base64 ciphertext>" }
                                       (written by dirless-syncer; replaces old PUT /snapshot)

GET  /snapshot/local                 → returns { "snapshot": "<base64 ciphertext or null>" }
PUT  /snapshot/local                 → body: { "snapshot": "<base64 ciphertext>" }
                                       (written by portal)

GET  /snapshot/public-key            → returns { "age_public_key": "<age public key or null>" }
PUT  /snapshot/public-key            → body: { "age_public_key": "<age public key string>" }
                                       (called once during key setup; idempotent)
```

The old `PUT /snapshot` endpoint should be kept as a redirect or alias during the transition
period and removed once the syncer is updated.

Future cloud sources would follow the same pattern:
```
PUT /snapshot/azure-active-directory
PUT /snapshot/google-workspace
```
The agent fetches all known source endpoints and merges them. Local blob has the highest
priority — it wins over any cloud source on conflict. Cloud-vs-cloud tie-breaking is TBD.

**Duplicate tracking field on snapshot record**: `duplicate_usernames TEXT` (nullable,
JSON array of strings). Written by the agent via:

```
PUT /snapshot/duplicates      → body: { "duplicate_usernames": ["alice", "bob"] }
                                (empty array = no duplicates)
```

The portal reads this field to show the banner without requiring the user to decrypt.

### 2. Agent (`dirless-agent`) — core merge logic

**On each sync tick:**

1. Fetch syncer blob (`GET /snapshot/aws-identity-center`) — renamed endpoint.
2. Fetch local blob (`GET /snapshot/local`) — new.
3. Decrypt both blobs with the age private key. If either is null/empty, treat as empty
   user list. If decryption of the local blob fails, log a warning and proceed with only
   the syncer blob (do not crash).
4. Merge:
   - Start with local blob users.
   - For each syncer blob user: if username not in local set → add. If username collision
     → syncer wins (replace local entry), record the collision.
5. Write merged result to local TPDB (existing mechanism for NSS serving).
6. If collision set changed since last tick:
   - `PUT /snapshot/duplicates` with the new list.
   - If new collisions appeared (list grew): POST to ops API to trigger duplicate
     notification email. Include tenant_id in the request so the ops server can look up
     the customer email.

**New config key** (agent TOML, optional):
```toml
[local]
local_snapshot_enabled = true   # default true once feature is deployed
```

### 3. Portal (`dirless-ops` webui) — key setup + local blob CRUD + duplicate banner

#### Key setup page (`/portal/directory/setup`)

Shown when `GET /snapshot/public-key` returns null. Two options:
- Paste private key → derive public key → `PUT /snapshot/public-key`.
- Generate → create keypair → show private key with download button (one-time only) →
  `PUT /snapshot/public-key`.

After setup, redirect to the local users page.

#### Local users page (`/portal/directory/local-users`)

Requires the user to enter their age private key each session (same pattern as existing
snapshot decryption UX). With the key in hand:

- **List**: decrypt local blob → show users in a table.
- **Add user**: form (username, uid, full name, groups). Check against decrypted union of
  both blobs. On success → add to local list → re-encrypt → `PUT /snapshot/local`.
- **Edit user**: same decrypt → modify → re-encrypt → PUT flow.
- **Delete user**: same decrypt → remove → re-encrypt → PUT flow.

#### Duplicate banner

On the customer dashboard / directory overview page, if `duplicate_usernames` is non-empty
(fetched from the snapshot record, no decryption needed):

```
⚠ 3 users in your local directory are also in IAM Identity Center (local entry takes effect).
  [Decrypt with your age key to see the list →]
```

Clicking the link goes to the local users page where the duplicate entries are highlighted.

#### Email notification (ops server side)

When the agent posts new duplicates, the ops server sends an email to the customer's
verified email address (via the existing notifier):

```
Subject: Duplicate users found in your Dirless directory

Hi <company>,

We detected that <N> user(s) in your manually-added directory list now also exist
in your IAM Identity Center directory. Your manually-added entries take effect for
these users — the IAM Identity Center versions are currently ignored.

Affected usernames: alice, bob

If you want IAM Identity Center to manage these users, log in to
portal.dirless.com → Directory → Local Users and remove them from your local list.

— The Dirless Team
```

### 4. Syncer (`dirless-syncer`) — no changes

The syncer switches from `PUT /snapshot` to `PUT /snapshot/aws-identity-center`. This is a
one-line URL change. It is not aware of the local blob.

---

## Data Shape

### Syncer blob (existing, unchanged)
```json
{
  "users": [
    { "name": "alice",  "uid": 1001, "shell": "/bin/bash", "groups": ["developers"] },
    { "name": "bob",    "uid": 1002, "shell": "/bin/bash", "groups": ["admins"] }
  ],
  "groups": [
    { "name": "developers", "gid": 2001 },
    { "name": "admins",     "gid": 2002 }
  ]
}
```

### Local blob (new, same shape)
```json
{
  "users": [
    { "name": "goatman", "uid": 100001, "shell": "/bin/bash", "groups": ["local-admins"] }
  ],
  "groups": [
    { "name": "local-admins", "gid": 100001 }
  ]
}
```

No `source` field is needed inside the JSON payload. The agent fetches blobs from separate
endpoints (`GET /snapshot/aws-identity-center`, `GET /snapshot/local`, and any future cloud
sources) and decrypts them independently. It always knows which users came from which blob
by virtue of which endpoint returned them — not from anything encoded in the ciphertext itself.

---

## UID/GID Allocation

- IAM IC UIDs/GIDs are assigned by the syncer (existing behaviour), allocated
  sequentially from 1000. This leaves 99,000 slots (1000–99999) before the local floor.
- Local UIDs/GIDs are chosen by the portal user at add time.
- The portal should suggest the next available UID/GID at or above **100,000** (the
  local user floor). This makes local users instantly recognisable in `id` / `getent`
  output and is consistent with how large Linux deployments (SSSD, FreeIPA) separate
  directory ranges.
- Portal warns if the entered UID/GID already appears in either blob.
- The floor (100,000) should be a named constant in the portal code, not a magic number.

---

## Implementation Order

1. **Backend**: add `local_snapshot` and `duplicate_usernames` fields + new endpoints.
2. **Agent**: fetch + decrypt + merge + duplicate reporting logic.
3. **Portal**: key setup page → local users CRUD → duplicate banner.
4. **Ops notifier**: new email template for duplicate notifications.

Test on staging end-to-end before deploying to production.

---

## Out of Scope (for now)

- Syncer auto-reporting real `aws_account_id` to ops during enrollment (avoids manual
  tenant_id alignment step). Track separately.
- Group-level deduplication (only username/uid conflicts handled for now).
- Bulk import of local users (CSV etc.).
