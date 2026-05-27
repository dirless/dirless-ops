class Portal::DirectoryPage < PortalLayout
  needs snapshot_blob : String?
  needs backend_error : String? = nil

  def page_title : String
    "Directory"
  end

  def active_nav : String
    "directory"
  end

  def content
    raw "<style>#{dir_css}</style>"

    if (err = @backend_error)
      div class: "banner banner-error" do
        text "⚠ Could not reach backend: #{err}"
      end
    end

    # Info banner
    div class: "banner banner-info" do
      text "Linux directory users for your Dirless environment. "
      strong "Your private key never leaves the browser"
      text " — decryption and re-encryption happen locally."
    end

    # Step 1: Private key
    div class: "dir-card" do
      div class: "dir-card-title" do
        text "Step 1 — Enter age private key"
      end
      label "Private key", for: "private-key-input", class: "dir-label"
      textarea id: "private-key-input", rows: "2",
        class: "dir-textarea",
        placeholder: "AGE-SECRET-KEY-1..." do
      end
      div class: "dir-row mt-s" do
        button id: "decrypt-btn", type: "button", class: "btn btn-primary" do
          text "Decrypt & load users"
        end
        span id: "decrypt-status", class: "dir-status" do
        end
      end
    end

    # Step 2: Manage users (hidden until decrypted)
    div id: "users-section", class: "hidden" do
      div class: "dir-card" do
        div class: "dir-row mb-s" do
          div class: "dir-card-title mb-0", id: "step2-title" do
            text "Step 2 — Manage users"
          end
          button id: "add-user-btn", type: "button", class: "btn btn-success" do
            text "+ Add user"
          end
        end

        # Duplicate warning
        div id: "duplicate-warning", class: "hidden banner banner-error mb-s" do
          text "A user with that username already exists."
        end

        # Add-user form
        div id: "add-user-form", class: "hidden dir-add-form mb-s" do
          div class: "dir-add-title" do
            text "New user"
          end
          div class: "dir-add-grid" do
            div do
              label "Username *", for: "new-username", class: "dir-label"
              input type: "text", id: "new-username", class: "dir-input", placeholder: "alice"
            end
            div do
              label "Display name", for: "new-gecos", class: "dir-label"
              input type: "text", id: "new-gecos", class: "dir-input", placeholder: "Alice Smith"
            end
            div do
              label "Shell", for: "new-shell", class: "dir-label"
              input type: "text", id: "new-shell", class: "dir-input", value: "/bin/bash"
            end
          end
          div class: "dir-row mt-s" do
            button id: "confirm-add-btn", type: "button", class: "btn btn-primary btn-sm" do
              text "Add"
            end
            button id: "cancel-add-btn", type: "button", class: "btn btn-ghost btn-sm" do
              text "Cancel"
            end
          end
        end

        # Users table
        div class: "table-wrap" do
          table class: "dir-table" do
            thead do
              tr do
                th "Username"
                th "Display name"
                th "Shell"
                th "UID"
                th ""
              end
            end
            tbody id: "users-tbody" do
            end
          end
        end

        div id: "no-users-msg", class: "hidden dir-empty" do
          text "No users yet. Click \"+ Add user\" to get started."
        end
      end

      # Save
      div class: "dir-row" do
        button id: "save-btn", type: "button", class: "btn btn-primary" do
          text "Encrypt & save"
        end
        span id: "save-status", class: "dir-status" do
        end
      end
    end

    # Hidden form for blob submission
    form id: "submit-form", action: "/directory", method: "post", class: "hidden" do
      input type: "hidden", name: "blob", id: "blob-input"
      input type: "hidden", name: "recipient", id: "recipient-input"
    end

    # Snapshot blob as JS variable
    script do
      raw "const SNAPSHOT_B64 = #{@snapshot_blob.to_json};"
    end

    # age-encryption + directory logic (ES module)
    script type: "module" do
      raw <<-'JAVASCRIPT'
import * as age from "https://esm.sh/age-encryption@0";

const UID_START  = 60001;
const GID_USERS  = 60001;
const GROUP_NAME = "dirless-users";

let users    = [];
let identity = null;

console.log("[dir] SNAPSHOT_B64 length:", SNAPSHOT_B64 ? SNAPSHOT_B64.length : 0);

// ── binary / base64 ─────────────────────────────────────────────────────────

function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToB64(bytes) {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

// ── gzip ─────────────────────────────────────────────────────────────────────

async function gunzip(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
  const chunks = [];
  const reader = stream.getReader();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
  }
  const total = chunks.reduce((s, c) => s + c.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) { out.set(c, off); off += c.length; }
  return out;
}

async function gzipBytes(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream("gzip"));
  const chunks = [];
  const reader = stream.getReader();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
  }
  const total = chunks.reduce((s, c) => s + c.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) { out.set(c, off); off += c.length; }
  return out;
}

// ── helpers ───────────────────────────────────────────────────────────────────

function esc(s) {
  return String(s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function setStatus(id, msg, cls) {
  const el = document.getElementById(id);
  el.textContent = msg;
  el.className = "dir-status " + cls;
}

// ── render users table ────────────────────────────────────────────────────────

function renderUsers() {
  const tbody = document.getElementById("users-tbody");
  const empty = document.getElementById("no-users-msg");
  document.getElementById("step2-title").textContent = users.length > 0
    ? "Step 2 — Manage users (" + users.length + ")"
    : "Step 2 — Manage users";
  tbody.innerHTML = "";

  if (users.length === 0) {
    empty.classList.remove("hidden");
    return;
  }
  empty.classList.add("hidden");

  users.forEach((u, i) => {
    const tr = document.createElement("tr");
    tr.innerHTML =
      `<td class="mono">${esc(u.username)}</td>` +
      `<td>${esc(u.gecos || "")}</td>` +
      `<td class="mono dim">${esc(u.shell || "/bin/bash")}</td>` +
      `<td class="dim">${u.uid}</td>` +
      `<td><button class="btn-link btn-danger" onclick="window.__delUser(${i})">Remove</button></td>`;
    tbody.appendChild(tr);
  });
}

window.__delUser = function(i) {
  if (!confirm(`Remove user "${users[i].username}"?`)) return;
  users.splice(i, 1);
  renderUsers();
};

function nextUid() {
  return users.length === 0 ? UID_START : Math.max(...users.map(u => u.uid)) + 1;
}

// ── decrypt ───────────────────────────────────────────────────────────────────

async function handleDecrypt() {
  const keyText = document.getElementById("private-key-input").value.trim();
  if (!keyText) {
    setStatus("decrypt-status", "Enter your private key first.", "status-error");
    return;
  }
  setStatus("decrypt-status", "Decrypting…", "status-muted");
  try {
    identity = keyText;
    if (SNAPSHOT_B64) {
      const d = new age.Decrypter();
      d.addIdentity(identity);
      const gzipped   = await d.decrypt(b64ToBytes(SNAPSHOT_B64), "uint8array");
      const jsonBytes = await gunzip(gzipped);
      const payload   = JSON.parse(new TextDecoder().decode(jsonBytes));
      users = Array.isArray(payload.users) ? payload.users : [];
      console.log("[dir] decrypted", users.length, "users");
    } else {
      users = [];
    }
    renderUsers();
    document.getElementById("users-section").classList.remove("hidden");
    setStatus("decrypt-status",
      `Loaded ${users.length} user${users.length === 1 ? "" : "s"}.`,
      "status-ok");
  } catch (err) {
    setStatus("decrypt-status", "Error: " + err.message, "status-error");
  }
}

// ── add user ──────────────────────────────────────────────────────────────────

function handleAddUser() {
  const username = document.getElementById("new-username").value.trim();
  const gecos    = document.getElementById("new-gecos").value.trim();
  const shell    = document.getElementById("new-shell").value.trim() || "/bin/bash";
  const warn     = document.getElementById("duplicate-warning");

  if (!username) { alert("Username is required."); return; }
  if (users.some(u => u.username === username)) {
    warn.classList.remove("hidden"); return;
  }
  warn.classList.add("hidden");

  users.push({
    username, uid: nextUid(), gid: GID_USERS,
    gecos: gecos || username, home: "/home/" + username, shell,
  });
  console.log("[dir] added user, total:", users.length);
  renderUsers();
  document.getElementById("add-user-form").classList.add("hidden");
  document.getElementById("new-username").value = "";
  document.getElementById("new-gecos").value    = "";
  document.getElementById("new-shell").value    = "/bin/bash";
}

// ── save ──────────────────────────────────────────────────────────────────────

async function handleSave() {
  if (!identity) {
    setStatus("save-status", "Decrypt first.", "status-error"); return;
  }
  console.log("[dir] saving", users.length, "users:", users.map(u => u.username));
  setStatus("save-status", "Encrypting " + users.length + " user" + (users.length === 1 ? "" : "s") + "…", "status-muted");
  try {
    const payload   = {
      users,
      groups: [{ name: GROUP_NAME, gid: GID_USERS, members: users.map(u => u.username) }],
    };
    const jsonBytes = new TextEncoder().encode(JSON.stringify(payload));
    const gzipped   = await gzipBytes(jsonBytes);
    const e = new age.Encrypter();
    const recipient = await age.identityToRecipient(identity);
    e.addRecipient(recipient);
    const cipher = await e.encrypt(gzipped);
    document.getElementById("blob-input").value = bytesToB64(cipher);
    document.getElementById("recipient-input").value = recipient;
    document.getElementById("submit-form").submit();
  } catch (err) {
    setStatus("save-status", "Error: " + err.message, "status-error");
  }
}

// ── events ────────────────────────────────────────────────────────────────────

document.getElementById("decrypt-btn").addEventListener("click", handleDecrypt);
document.getElementById("save-btn").addEventListener("click", handleSave);
document.getElementById("add-user-btn").addEventListener("click", () => {
  document.getElementById("add-user-form").classList.toggle("hidden");
  document.getElementById("duplicate-warning").classList.add("hidden");
});
document.getElementById("confirm-add-btn").addEventListener("click", handleAddUser);
document.getElementById("cancel-add-btn").addEventListener("click", () => {
  document.getElementById("add-user-form").classList.add("hidden");
  document.getElementById("duplicate-warning").classList.add("hidden");
});
document.getElementById("new-username").addEventListener("keydown", e => {
  if (e.key === "Enter") handleAddUser();
});
JAVASCRIPT
    end
  end

  private def dir_css : String
    <<-CSS
    .banner {
      padding: 0.75rem 1rem;
      border-radius: 6px;
      font-size: 0.875rem;
      margin-bottom: 1.5rem;
      line-height: 1.5;
    }
    .banner-info {
      background: rgba(88, 166, 255, 0.1);
      border: 1px solid rgba(88, 166, 255, 0.3);
      color: var(--text-dim);
    }
    .banner-error {
      background: rgba(248, 81, 73, 0.1);
      border: 1px solid rgba(248, 81, 73, 0.3);
      color: #ff7b72;
    }
    .dir-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 1.5rem;
      margin-bottom: 1.5rem;
    }
    .dir-card-title {
      font-size: 0.9rem;
      font-weight: 700;
      color: var(--text);
      margin-bottom: 1rem;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      font-size: 0.78rem;
      color: var(--muted);
    }
    .mb-0 { margin-bottom: 0; }
    .mb-s { margin-bottom: 0.75rem; }
    .mt-s { margin-top: 0.75rem; }
    .dir-label {
      display: block;
      font-size: 0.8rem;
      font-weight: 600;
      color: var(--muted);
      margin-bottom: 0.35rem;
    }
    .dir-textarea {
      width: 100%;
      background: var(--surface2);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0.6rem 0.8rem;
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
      font-size: 0.85rem;
      color: var(--text);
      resize: vertical;
      outline: none;
    }
    .dir-textarea:focus {
      border-color: var(--accent);
    }
    .dir-input {
      width: 100%;
      background: var(--surface2);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0.45rem 0.7rem;
      font-size: 0.875rem;
      color: var(--text);
      outline: none;
    }
    .dir-input:focus {
      border-color: var(--accent);
    }
    .dir-row {
      display: flex;
      align-items: center;
      gap: 0.75rem;
    }
    .dir-status {
      font-size: 0.85rem;
    }
    .status-muted { color: var(--muted); }
    .status-ok    { color: var(--accent2); }
    .status-error { color: var(--danger); }
    .dir-add-form {
      background: var(--surface2);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 1rem;
    }
    .dir-add-title {
      font-size: 0.8rem;
      font-weight: 700;
      color: var(--muted);
      margin-bottom: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .dir-add-grid {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 0.75rem;
    }
    .dir-empty {
      font-size: 0.875rem;
      color: var(--muted);
      padding: 0.75rem 0;
      text-align: center;
    }
    .table-wrap { overflow-x: auto; }
    .dir-table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.875rem;
      margin-bottom: 0.75rem;
    }
    .dir-table thead tr {
      border-bottom: 1px solid var(--border);
    }
    .dir-table th {
      text-align: left;
      padding: 0.5rem 0.75rem;
      font-size: 0.75rem;
      font-weight: 600;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    .dir-table td {
      padding: 0.6rem 0.75rem;
      color: var(--text-dim);
      border-bottom: 1px solid var(--border);
    }
    .dir-table tbody tr:last-child td { border-bottom: none; }
    .dir-table tbody tr:hover td { background: var(--surface2); }
    .mono { font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; }
    .dim  { color: var(--muted); }
    .hidden { display: none !important; }
    .btn {
      padding: 0.45rem 1rem;
      border-radius: 6px;
      font-size: 0.875rem;
      font-weight: 600;
      cursor: pointer;
      border: none;
      font-family: inherit;
      transition: opacity 0.15s;
    }
    .btn:hover { opacity: 0.85; }
    .btn-sm { padding: 0.3rem 0.75rem; font-size: 0.8rem; }
    .btn-primary { background: var(--accent); color: #0d1117; }
    .btn-success { background: var(--accent2); color: #0d1117; }
    .btn-ghost {
      background: transparent;
      border: 1px solid var(--border);
      color: var(--muted);
    }
    .btn-link {
      background: none;
      border: none;
      font-size: 0.8rem;
      font-weight: 600;
      cursor: pointer;
      padding: 0;
      font-family: inherit;
    }
    .btn-danger { color: var(--danger); }
    .btn-danger:hover { text-decoration: underline; }
    CSS
  end
end
