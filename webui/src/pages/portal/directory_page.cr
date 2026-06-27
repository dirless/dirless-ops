class Portal::DirectoryPage < PortalLayout
  needs cloud_snapshot_blob : String?
  needs local_snapshot_blob : String?
  needs age_public_key : String? = nil
  needs age_public_key_source : String? = nil
  needs backend_error : String? = nil
  needs provisioned : Bool = true
  needs recently_created : Bool = false
  # UIDs/GIDs for locally-added users start above this floor so they never
  # collide with IAM Identity Center-allocated IDs (which start at 1000).
  LOCAL_UID_FLOOR  = 100_000
  LOCAL_GROUP_NAME = "dirless-local"
  LOCAL_GROUP_GID  = 100_000

  def page_title : String
    "Directory"
  end

  def active_nav : String
    "directory"
  end

  def content
    raw "<style>#{dir_css}</style>"

    if @backend_error
      if @recently_created
        div class: "banner banner-info" do
          text "⚙ Your backend is still being provisioned. This usually takes about 10 minutes - check back shortly."
        end
        return
      else
        div class: "banner banner-info" do
          text "⚙ Your backend is currently unreachable. This is usually temporary - check back in a few minutes. If the problem persists, contact support."
        end
      end
    end

    unless @provisioned
      div class: "banner banner-info" do
        text "⚙ Your backend is still being provisioned. This usually takes about 10 minutes - check back shortly."
      end
      return
    end

    dir_panel_content
  end

  private def dir_panel_content
    div class: "banner banner-info" do
      text "Manage your Dirless directory. "
      strong "Your private key never leaves the browser"
      text " - decryption and re-encryption happen locally. "
      a "Don't have a key? Learn how to generate one →", href: "https://dirless.com/age-keypair.html", target: "_blank"
    end

    # Prompt to provide a key when none is registered yet
    if @age_public_key.nil?
      div id: "keygen-card", class: "dir-card" do
        div class: "dir-card-title" do
          text "No key registered yet"
        end
        para class: "dir-keygen-desc" do
          text "Paste your age private key below to register it and begin editing your directory."
        end
      end
    end

    # Step 1: Private key
    div class: "dir-card" do
      div class: "dir-card-title" do
        text "Enter age private key"
      end
      label "Private key", for: "private-key-input", class: "dir-label"
      if key = @age_public_key
        div class: "dir-key-hint" do
          source_label = case @age_public_key_source
                         when "enrollment" then "dirless-cli enroll"
                         when "syncer"     then "the syncer"
                         else                   "an unknown source"
                         end
          text "Originally registered via #{source_label}: "
          code key
          text " - paste the matching private key below."
        end
        div class: "dir-recover-wrap" do
          a "Lost your key?", href: "#", id: "recover-toggle", class: "dir-recover-link"
          div id: "recover-section", class: "hidden dir-recover-box" do
            para class: "dir-recover-warning" do
              text "Generate a new age keypair, then re-enroll your host with "
              code "dirless-cli enroll --age-key /path/to/new.key --overwrite-existing"
              text ". Come back and paste the new key above."
            end
          end
        end
      end
      textarea id: "private-key-input", rows: "2",
        class: "dir-textarea",
        placeholder: "AGE-SECRET-KEY-1..." do
      end
      div class: "dir-row mt-s" do
        button id: "decrypt-btn", type: "button", class: "btn btn-primary" do
          text "Decrypt & load"
        end
        span id: "decrypt-status", class: "dir-status" do
        end
      end
    end

    # Revealed after decryption
    div id: "directory-section", class: "hidden" do
      # Duplicate banner (computed after decryption)
      div id: "dup-banner", class: "hidden banner banner-warning mb-0" do
        span id: "dup-banner-text" do
        end
        text " Local entries take effect for these users - "
        a "review below", href: "#local-section"
        text "."
      end

      # Cloud users (read-only)
      div id: "cloud-section", class: "dir-card" do
        div class: "dir-card-title" do
          text "IAM Identity Center users"
          span id: "cloud-count-badge", class: "dir-badge" do
          end
        end
        div id: "cloud-empty", class: "hidden dir-empty" do
          text "No IAM Identity Center snapshot yet - the syncer hasn't run."
        end
        div id: "cloud-table-wrap", class: "hidden table-wrap" do
          table class: "dir-table" do
            thead do
              tr do
                th "Username"
                th "Display name"
                th "Email"
                th "UID"
                th "Shell"
                th "SSH Keys"
              end
            end
            tbody id: "cloud-tbody" do
            end
          end
        end
      end

      # Local users (editable)
      div id: "local-section", class: "dir-card" do
        div class: "dir-row mb-s" do
          div class: "dir-card-title mb-0" do
            text "Local users"
            span id: "local-count-badge", class: "dir-badge" do
            end
          end
          button id: "add-user-btn", type: "button", class: "btn btn-success" do
            text "+ Add user"
          end
        end

        div id: "add-conflict-warning", class: "hidden banner banner-error mb-s" do
          text "A user with that username already exists (in cloud or local users)."
        end

        div id: "add-user-form", class: "hidden dir-add-form mb-s" do
          div class: "dir-add-title" do
            text "New local user"
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
              label "Email", for: "new-email", class: "dir-label"
              input type: "email", id: "new-email", class: "dir-input", placeholder: "alice@example.com"
            end
            div do
              label "Shell", for: "new-shell", class: "dir-label"
              input type: "text", id: "new-shell", class: "dir-input", value: "/bin/bash"
            end
          end
          div class: "mt-s" do
            label "SSH public keys", for: "new-ssh-keys", class: "dir-label"
            textarea id: "new-ssh-keys", class: "dir-textarea", rows: "2",
              placeholder: "One key per line (optional - can be added later)" do
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

        div class: "table-wrap" do
          table class: "dir-table" do
            thead do
              tr do
                th "Username"
                th "Display name"
                th "Email"
                th "UID"
                th "Shell"
                th "SSH Keys"
                th ""
              end
            end
            tbody id: "local-tbody" do
            end
          end
        end

        div id: "local-empty", class: "dir-empty" do
          text "No local users yet. Click \"+ Add user\" to get started."
        end
      end

      # Local groups (editable)
      div id: "groups-section", class: "dir-card" do
        div class: "dir-row mb-s" do
          div class: "dir-card-title mb-0" do
            text "Local groups"
            span id: "groups-count-badge", class: "dir-badge" do
            end
          end
          button id: "add-group-btn", type: "button", class: "btn btn-success" do
            text "+ Add group"
          end
        end
        para class: "dir-groups-desc" do
          text "Create groups and assign local users to them. Group names are used in Settings "
          a "host access rules", href: "/settings"
          text " to control which users can log into which hosts."
        end

        div id: "add-group-form", class: "hidden dir-add-form mb-s" do
          div class: "dir-add-title" do
            text "New group"
          end
          div class: "dir-row" do
            input type: "text", id: "new-group-name", class: "dir-input", placeholder: "admins"
            button id: "confirm-add-group-btn", type: "button", class: "btn btn-primary btn-sm" do
              text "Add"
            end
            button id: "cancel-add-group-btn", type: "button", class: "btn btn-ghost btn-sm" do
              text "Cancel"
            end
          end
          div id: "add-group-error", class: "hidden dir-field-error" do
          end
        end

        div id: "groups-list" do
        end
        div id: "groups-empty", class: "dir-empty" do
          text "No custom groups yet. Click \"+ Add group\" to create one."
        end
      end

      div class: "dir-row" do
        button id: "save-btn", type: "button", class: "btn btn-primary" do
          text "Encrypt & save"
        end
        span id: "save-status", class: "dir-status" do
        end
      end
    end

    form id: "submit-form", action: "/directory", method: "post", enctype: "multipart/form-data", class: "hidden" do
      input type: "hidden", name: "blob", id: "blob-input"
      input type: "hidden", name: "recipient", id: "recipient-input"
    end

    script do
      raw "const CLOUD_SNAPSHOT_B64 = #{@cloud_snapshot_blob.to_json};"
      raw "const LOCAL_SNAPSHOT_B64 = #{@local_snapshot_blob.to_json};"
      raw "const LOCAL_UID_FLOOR = #{LOCAL_UID_FLOOR};"
      raw "const LOCAL_GROUP_NAME = #{LOCAL_GROUP_NAME.to_json};"
      raw "const LOCAL_GROUP_GID  = #{LOCAL_GROUP_GID};"
    end

    script type: "module" do
      raw <<-'JAVASCRIPT'
import * as age from "https://esm.sh/age-encryption@0";

let cloudUsers  = [];
let localUsers  = [];
let localGroups = [];  // [{name, gid, members: [username,...]}] - custom groups only
let sshKeys     = {};  // username → newline-separated public keys string
let identity    = null;

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

async function decryptBlob(b64, key) {
  if (!b64) return { users: [], groups: [], sshKeys: {} };
  const d = new age.Decrypter();
  d.addIdentity(key);
  const gzipped   = await d.decrypt(b64ToBytes(b64), "uint8array");
  const jsonBytes = await gunzip(gzipped);
  const payload   = JSON.parse(new TextDecoder().decode(jsonBytes));
  // Filter out the auto-managed dirless-local group - we rebuild it on every save.
  const groups = Array.isArray(payload.groups)
    ? payload.groups.filter(g => g.name !== LOCAL_GROUP_NAME)
    : [];
  return {
    users:   Array.isArray(payload.users) ? payload.users : [],
    groups,
    sshKeys: (payload.ssh_keys && typeof payload.ssh_keys === "object") ? payload.ssh_keys : {},
  };
}

// ── SSH key validation ────────────────────────────────────────────────────────

const SSH_KEY_TYPES = new Set([
  "ssh-rsa", "ssh-dss",
  "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521",
  "ssh-ed25519",
  "sk-ssh-ed25519@openssh.com",
  "sk-ecdsa-sha2-nistp256@openssh.com",
]);

// Validates all non-empty lines as SSH public keys.
// Returns { fingerprints: string[] } on success, or { error: string } on the
// first invalid line.  Fingerprints are computed via SHA-256 of the raw key
// blob (same algorithm as `ssh-keygen -l -E sha256`).
async function validateSshKeys(text) {
  const lines = text.split("\n");
  const fingerprints = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    const parts = line.split(/\s+/);
    if (parts.length < 2) return { error: `Line ${i + 1}: missing base64 key data` };
    if (!SSH_KEY_TYPES.has(parts[0])) return { error: `Line ${i + 1}: unknown key type "${parts[0]}"` };
    let decoded;
    try {
      decoded = Uint8Array.from(atob(parts[1]), c => c.charCodeAt(0));
    } catch {
      return { error: `Line ${i + 1}: invalid base64` };
    }
    // Verify the wire-format type inside the blob matches the header.
    // First 4 bytes are a big-endian uint32 length of the algorithm name.
    if (decoded.length < 4) return { error: `Line ${i + 1}: key data too short` };
    const typeLen = (decoded[0] << 24 | decoded[1] << 16 | decoded[2] << 8 | decoded[3]) >>> 0;
    if (4 + typeLen > decoded.length) return { error: `Line ${i + 1}: key data truncated` };
    const wireType = new TextDecoder().decode(decoded.slice(4, 4 + typeLen));
    if (wireType !== parts[0]) {
      return { error: `Line ${i + 1}: key type "${parts[0]}" does not match key data (says "${wireType}")` };
    }
    // Compute SHA-256 fingerprint of the raw key blob - same as ssh-keygen -l -E sha256.
    try {
      const hashBuf = await crypto.subtle.digest("SHA-256", decoded);
      const b64 = btoa(String.fromCharCode(...new Uint8Array(hashBuf))).replace(/=+$/, "");
      fingerprints.push(`SHA256:${b64}`);
    } catch {
      return { error: `Line ${i + 1}: could not compute fingerprint` };
    }
  }
  return { fingerprints };
}

// ── SSH key helpers ───────────────────────────────────────────────────────────

function keyCount(username) {
  const s = sshKeys[username] || "";
  return s.split("\n").filter(l => l.trim().length > 0).length;
}

function sshKeysBtnLabel(username) {
  const n = keyCount(username);
  return n > 0 ? `Keys (${n})` : "Add keys";
}

// Save the current value of any open SSH key textareas back into sshKeys.
// Must be called before innerHTML is cleared during a re-render.
function saveAllOpenSshKeys() {
  document.querySelectorAll(".ssh-key-row:not(.hidden)").forEach(row => {
    const ta = row.querySelector("textarea");
    if (!ta) return;
    const username = ta.dataset.username;
    const val = ta.value.trim();
    if (val) sshKeys[username] = val;
    else delete sshKeys[username];
  });
}

window.__toggleSsh = function(username) {
  const row = document.getElementById("ssh-row-" + username);
  if (!row) return;
  row.classList.toggle("hidden");
  if (!row.classList.contains("hidden")) row.querySelector("textarea").focus();
};

window.__saveSshKeys = async function(username) {
  const ta  = document.getElementById("ssh-ta-" + username);
  const msg = document.getElementById("ssh-err-" + username);
  if (!ta) return;
  const val = ta.value.trim();
  if (!val) {
    delete sshKeys[username];
    if (msg) { msg.textContent = ""; msg.className = "ssh-key-error hidden"; }
    return;
  }
  const result = await validateSshKeys(val);
  if (result.error) {
    if (msg) { msg.textContent = result.error; msg.className = "ssh-key-error"; }
    return;
  }
  sshKeys[username] = val;
  if (msg) {
    msg.textContent = result.fingerprints.join("\n");
    msg.className = "ssh-key-ok";
  }
};

// ── duplicate detection ───────────────────────────────────────────────────────

function findDuplicates() {
  const cloudSet = new Set(cloudUsers.map(u => u.username));
  return localUsers.filter(u => cloudSet.has(u.username)).map(u => u.username);
}

function updateDuplicateBanner() {
  const dups = findDuplicates();
  const banner = document.getElementById("dup-banner");
  if (dups.length === 0) {
    banner.classList.add("hidden");
  } else {
    document.getElementById("dup-banner-text").textContent =
      `⚠ ${dups.length} local user${dups.length === 1 ? "" : "s"} (${dups.join(", ")}) also exist in IAM Identity Center.`;
    banner.classList.remove("hidden");
  }
}

// ── render ────────────────────────────────────────────────────────────────────

function renderCloud() {
  saveAllOpenSshKeys();
  const tbody  = document.getElementById("cloud-tbody");
  const empty  = document.getElementById("cloud-empty");
  const wrap   = document.getElementById("cloud-table-wrap");
  const badge  = document.getElementById("cloud-count-badge");

  badge.textContent = cloudUsers.length > 0 ? ` (${cloudUsers.length})` : "";

  if (cloudUsers.length === 0) {
    empty.classList.remove("hidden");
    wrap.classList.add("hidden");
    return;
  }
  empty.classList.add("hidden");
  wrap.classList.remove("hidden");
  tbody.innerHTML = "";
  cloudUsers.forEach(u => {
    const tr = document.createElement("tr");
    tr.innerHTML =
      `<td class="mono">${esc(u.username)}</td>` +
      `<td>${esc(u.gecos || "")}</td>` +
      `<td class="dim">${esc(u.email || "")}</td>` +
      `<td class="dim">${u.uid}</td>` +
      `<td class="mono dim">${esc(u.shell || "/bin/bash")}</td>` +
      `<td><button class="btn-link btn-ssh" onclick="window.__toggleSsh('${esc(u.username)}')">${sshKeysBtnLabel(u.username)}</button></td>`;
    tbody.appendChild(tr);
    const sshTr = document.createElement("tr");
    sshTr.className = "ssh-key-row hidden";
    sshTr.id = "ssh-row-" + u.username;
    sshTr.innerHTML =
      `<td colspan="6" class="ssh-key-cell">` +
      `<textarea class="dir-textarea" id="ssh-ta-${esc(u.username)}" data-username="${esc(u.username)}" rows="3" ` +
      `placeholder="One public key per line (e.g. ssh-ed25519 AAAA...)" ` +
      `oninput="window.__saveSshKeys('${esc(u.username)}')" ` +
      `onblur="window.__saveSshKeys('${esc(u.username)}')">${esc(sshKeys[u.username] || "")}</textarea>` +
      `<div id="ssh-err-${esc(u.username)}" class="ssh-key-error hidden"></div></td>`;
    tbody.appendChild(sshTr);
  });
}

function renderLocal() {
  saveAllOpenSshKeys();
  const tbody = document.getElementById("local-tbody");
  const empty = document.getElementById("local-empty");
  const badge = document.getElementById("local-count-badge");
  const dupSet = new Set(findDuplicates());

  badge.textContent = localUsers.length > 0 ? ` (${localUsers.length})` : "";
  tbody.innerHTML = "";

  if (localUsers.length === 0) {
    empty.classList.remove("hidden");
    return;
  }
  empty.classList.add("hidden");

  localUsers.forEach((u, i) => {
    const isDup = dupSet.has(u.username);
    const tr = document.createElement("tr");
    if (isDup) tr.classList.add("row-dup");
    tr.innerHTML =
      `<td class="mono">${esc(u.username)}${isDup ? ' <span class="dup-tag">duplicate</span>' : ""}</td>` +
      `<td>${esc(u.gecos || "")}</td>` +
      `<td class="dim">${esc(u.email || "")}</td>` +
      `<td class="dim">${u.uid}</td>` +
      `<td class="mono dim">${esc(u.shell || "/bin/bash")}</td>` +
      `<td><button class="btn-link btn-ssh" onclick="window.__toggleSsh('${esc(u.username)}')">${sshKeysBtnLabel(u.username)}</button></td>` +
      `<td><button class="btn-link btn-danger" onclick="window.__delUser(${i})">Remove</button></td>`;
    tbody.appendChild(tr);
    const sshTr = document.createElement("tr");
    sshTr.className = "ssh-key-row hidden";
    sshTr.id = "ssh-row-" + u.username;
    sshTr.innerHTML =
      `<td colspan="7" class="ssh-key-cell">` +
      `<textarea class="dir-textarea" id="ssh-ta-${esc(u.username)}" data-username="${esc(u.username)}" rows="3" ` +
      `placeholder="One public key per line (e.g. ssh-ed25519 AAAA...)" ` +
      `oninput="window.__saveSshKeys('${esc(u.username)}')" ` +
      `onblur="window.__saveSshKeys('${esc(u.username)}')">${esc(sshKeys[u.username] || "")}</textarea>` +
      `<div id="ssh-err-${esc(u.username)}" class="ssh-key-error hidden"></div></td>`;
    tbody.appendChild(sshTr);
  });
}

function renderAll() {
  renderCloud();
  renderLocal();
  renderGroups();
  updateDuplicateBanner();
}

window.__delUser = function(i) {
  if (!confirm(`Remove local user "${localUsers[i].username}"?`)) return;
  localUsers.splice(i, 1);
  renderAll();
};

function nextUid() {
  const localMax = localUsers.length === 0 ? 0 : Math.max(...localUsers.map(u => u.uid));
  return Math.max(LOCAL_UID_FLOOR + 1, localMax + 1);
}

function nextGid() {
  const base = LOCAL_GROUP_GID + 1;  // custom groups start at 100001
  const usedGids = localGroups.map(g => g.gid);
  let gid = base;
  while (usedGids.includes(gid)) gid++;
  return gid;
}

function renderGroups() {
  const list  = document.getElementById("groups-list");
  const empty = document.getElementById("groups-empty");
  const badge = document.getElementById("groups-count-badge");
  badge.textContent = localGroups.length > 0 ? ` (${localGroups.length})` : "";

  if (localGroups.length === 0) {
    list.innerHTML = "";
    empty.classList.remove("hidden");
    return;
  }
  empty.classList.add("hidden");

  const localUsernames = localUsers.map(u => u.username);
  list.innerHTML = localGroups.map((g, gi) => {
    const memberTags = g.members.map(m =>
      `<span class="grp-member-tag">${esc(m)}<button class="grp-member-remove" onclick="window.__removeFromGroup(${gi},'${esc(m)}')" title="Remove">x</button></span>`
    ).join("");
    const available = localUsernames.filter(u => !g.members.includes(u));
    const addSelect = available.length > 0
      ? `<select class="grp-add-select" onchange="window.__addToGroup(${gi}, this)">
           <option value="">+ add member</option>
           ${available.map(u => `<option value="${esc(u)}">${esc(u)}</option>`).join("")}
         </select>`
      : "";
    return `
      <div class="grp-card">
        <div class="grp-header">
          <span class="grp-name">${esc(g.name)}</span>
          <span class="grp-gid">GID ${g.gid}</span>
          <button class="btn-link btn-danger grp-delete-btn" onclick="window.__deleteGroup(${gi})">Delete group</button>
        </div>
        <div class="grp-members">
          ${memberTags}
          ${addSelect}
          ${g.members.length === 0 && available.length === 0 ? '<span class="grp-no-users">No local users exist yet.</span>' : ""}
        </div>
      </div>`;
  }).join("");
}

window.__addToGroup = function(gi, select) {
  const username = select.value;
  if (!username) return;
  if (!localGroups[gi].members.includes(username)) {
    localGroups[gi].members.push(username);
    renderGroups();
  }
};

window.__removeFromGroup = function(gi, username) {
  localGroups[gi].members = localGroups[gi].members.filter(m => m !== username);
  renderGroups();
};

window.__deleteGroup = function(gi) {
  if (!confirm(`Delete group "${localGroups[gi].name}"?`)) return;
  localGroups.splice(gi, 1);
  renderGroups();
};

function handleAddGroup() {
  const input = document.getElementById("new-group-name");
  const errEl = document.getElementById("add-group-error");
  const name  = input.value.trim().toLowerCase().replace(/[^a-z0-9_-]/g, "");
  errEl.classList.add("hidden");

  if (!name) {
    errEl.textContent = "Group name is required.";
    errEl.classList.remove("hidden");
    return;
  }
  if (name === LOCAL_GROUP_NAME) {
    errEl.textContent = `"${LOCAL_GROUP_NAME}" is reserved.`;
    errEl.classList.remove("hidden");
    return;
  }
  if (localGroups.some(g => g.name === name)) {
    errEl.textContent = `Group "${name}" already exists.`;
    errEl.classList.remove("hidden");
    return;
  }
  localGroups.push({ name, gid: nextGid(), members: [] });
  input.value = "";
  document.getElementById("add-group-form").classList.add("hidden");
  renderGroups();
}

// ── decrypt ───────────────────────────────────────────────────────────────────

async function handleDecrypt() {
  const keyText = document.getElementById("private-key-input").value.trim();
  if (!keyText) {
    setStatus("decrypt-status", "Enter your private key first.", "status-error");
    return;
  }
  if (!keyText.startsWith("AGE-SECRET-KEY-1")) {
    setStatus("decrypt-status", "Invalid key: must start with AGE-SECRET-KEY-1", "status-error");
    return;
  }
  if (keyText.length !== 74) {
    setStatus("decrypt-status", `Invalid key: expected 74 characters, got ${keyText.length}`, "status-error");
    return;
  }
  try {
    await age.identityToRecipient(keyText);
  } catch (err) {
    setStatus("decrypt-status", "Invalid key: " + err.message, "status-error");
    return;
  }
  setStatus("decrypt-status", "Decrypting…", "status-muted");
  try {
    identity = keyText;
    const [cloudResult, localResult] = await Promise.all([
      decryptBlob(CLOUD_SNAPSHOT_B64, identity),
      decryptBlob(LOCAL_SNAPSHOT_B64, identity),
    ]);
    cloudUsers  = cloudResult.users;
    localUsers  = localResult.users;
    localGroups = localResult.groups;
    // Merge ssh_keys; local snapshot wins on conflict
    sshKeys = Object.assign({}, cloudResult.sshKeys, localResult.sshKeys);
    renderAll();
    document.getElementById("directory-section").classList.remove("hidden");
    const total = cloudUsers.length + localUsers.length;
    setStatus("decrypt-status",
      `Loaded ${cloudUsers.length} cloud + ${localUsers.length} local user${total === 1 ? "" : "s"}.`,
      "status-ok");
  } catch (err) {
    setStatus("decrypt-status", "Error: " + err.message, "status-error");
  }
}

// ── add user ──────────────────────────────────────────────────────────────────

async function handleAddUser() {
  const username = document.getElementById("new-username").value.trim();
  const gecos    = document.getElementById("new-gecos").value.trim();
  const email    = document.getElementById("new-email").value.trim();
  const shell    = document.getElementById("new-shell").value.trim() || "/bin/bash";
  const keys     = document.getElementById("new-ssh-keys").value.trim();
  const warn     = document.getElementById("add-conflict-warning");

  if (!username) { alert("Username is required."); return; }

  const allUsernames = new Set([
    ...cloudUsers.map(u => u.username),
    ...localUsers.map(u => u.username),
  ]);
  if (allUsernames.has(username)) {
    warn.classList.remove("hidden");
    return;
  }
  warn.classList.add("hidden");

  if (email) {
    const allEmails = [
      ...cloudUsers.map(u => u.email).filter(Boolean),
      ...localUsers.map(u => u.email).filter(Boolean),
    ];
    if (allEmails.includes(email.toLowerCase())) {
      alert(`That email address "${email}" is already assigned to another user.`);
      return;
    }
  }

  if (keys) {
    const result = await validateSshKeys(keys);
    if (result.error) { alert("Invalid SSH key: " + result.error); return; }
    sshKeys[username] = keys;
  }

  localUsers.push({
    username,
    uid:   nextUid(),
    gid:   LOCAL_GROUP_GID,
    gecos: gecos || username,
    home:  "/home/" + username,
    shell,
    email: email || null,
  });
  renderAll();
  document.getElementById("add-user-form").classList.add("hidden");
  document.getElementById("new-username").value  = "";
  document.getElementById("new-gecos").value     = "";
  document.getElementById("new-email").value     = "";
  document.getElementById("new-shell").value     = "/bin/bash";
  document.getElementById("new-ssh-keys").value  = "";
}

// ── save (local blob only) ────────────────────────────────────────────────────

async function handleSave() {
  if (!identity) {
    setStatus("save-status", "Decrypt first.", "status-error");
    return;
  }
  // Block save if any local user email duplicates a cloud or other local user email.
  const allEmails = [
    ...cloudUsers.map(u => u.email).filter(Boolean),
    ...localUsers.map(u => u.email).filter(Boolean),
  ];
  const emailDups = localUsers
    .filter(u => u.email && allEmails.filter(e => e === u.email).length > 1)
    .map(u => u.email);
  if (emailDups.length > 0) {
    const unique = [...new Set(emailDups)];
    setStatus("save-status", `Cannot save: duplicate email${unique.length === 1 ? "" : "s"} - ${unique.join(", ")}`, "status-error");
    return;
  }

  // Validate and flush any open SSH key textareas before encrypting
  for (const row of document.querySelectorAll(".ssh-key-row:not(.hidden)")) {
    const ta = row.querySelector("textarea");
    if (!ta) continue;
    const val = ta.value.trim();
    if (!val) continue;
    const result = await validateSshKeys(val);
    if (result.error) {
      const username = ta.dataset.username;
      setStatus("save-status", `SSH key error for ${username}: ${result.error}`, "status-error");
      ta.focus();
      return;
    }
  }
  saveAllOpenSshKeys();
  setStatus("save-status",
    "Encrypting " + localUsers.length + " local user" + (localUsers.length === 1 ? "" : "s") + "…",
    "status-muted");
  try {
    // dirless-local always contains every local user (backward compat + catch-all).
    // Custom groups are saved alongside it with only their explicitly assigned members.
    const autoGroup = localUsers.length > 0
      ? [{ name: LOCAL_GROUP_NAME, gid: LOCAL_GROUP_GID, members: localUsers.map(u => u.username) }]
      : [];
    // Drop members who no longer exist as local users.
    const validUsernames = new Set(localUsers.map(u => u.username));
    const cleanedGroups  = localGroups.map(g => ({
      ...g,
      members: g.members.filter(m => validUsernames.has(m)),
    }));
    const payload = {
      users:    localUsers,
      groups:   [...autoGroup, ...cleanedGroups],
      ssh_keys: sshKeys,
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

// ── key recovery ──────────────────────────────────────────────────────────────

const recoverToggle = document.getElementById("recover-toggle");
if (recoverToggle) {
  recoverToggle.addEventListener("click", e => {
    e.preventDefault();
    document.getElementById("recover-section").classList.toggle("hidden");
  });
}

// ── events ────────────────────────────────────────────────────────────────────

document.getElementById("decrypt-btn").addEventListener("click", handleDecrypt);
document.getElementById("save-btn").addEventListener("click", handleSave);
document.getElementById("add-user-btn").addEventListener("click", () => {
  document.getElementById("add-user-form").classList.toggle("hidden");
  document.getElementById("add-conflict-warning").classList.add("hidden");
});
document.getElementById("confirm-add-btn").addEventListener("click", handleAddUser);
document.getElementById("cancel-add-btn").addEventListener("click", () => {
  document.getElementById("add-user-form").classList.add("hidden");
  document.getElementById("add-conflict-warning").classList.add("hidden");
});
document.getElementById("new-username").addEventListener("keydown", e => {
  if (e.key === "Enter") handleAddUser();
});
document.getElementById("add-group-btn").addEventListener("click", () => {
  document.getElementById("add-group-form").classList.toggle("hidden");
  document.getElementById("add-group-error").classList.add("hidden");
  document.getElementById("new-group-name").focus();
});
document.getElementById("confirm-add-group-btn").addEventListener("click", handleAddGroup);
document.getElementById("cancel-add-group-btn").addEventListener("click", () => {
  document.getElementById("add-group-form").classList.add("hidden");
  document.getElementById("add-group-error").classList.add("hidden");
});
document.getElementById("new-group-name").addEventListener("keydown", e => {
  if (e.key === "Enter") handleAddGroup();
});
JAVASCRIPT
      raw %q(
// Sort users alphabetically before rendering
const __origRenderAll = renderAll;
renderAll = function() {
  cloudUsers.sort((a, b) => a.username.localeCompare(b.username));
  localUsers.sort((a, b) => a.username.localeCompare(b.username));
  __origRenderAll();
};
)
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
    .banner-warning {
      background: rgba(255, 166, 0, 0.1);
      border: 1px solid rgba(255, 166, 0, 0.3);
      color: #e3a700;
      margin-bottom: 1.25rem;
    }
    .mb-0 { margin-bottom: 0 !important; }
    .mb-s { margin-bottom: 0.75rem; }
    .mt-s { margin-top: 0.75rem; }
    .dir-badge {
      font-size: 0.75rem;
      font-weight: 500;
      color: var(--muted);
    }
    .dir-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 1.5rem;
      margin-bottom: 1.5rem;
    }
    .dir-card-title {
      font-size: 0.78rem;
      font-weight: 700;
      color: var(--muted);
      margin-bottom: 1rem;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .dir-label {
      display: block;
      font-size: 0.8rem;
      font-weight: 600;
      color: var(--muted);
      margin-bottom: 0.35rem;
    }
    .dir-keygen-desc {
      font-size: 0.875rem;
      color: var(--text-dim);
      margin: 0 0 1rem;
      line-height: 1.5;
    }
    .dir-recover-wrap { margin-top: 0.5rem; }
    .dir-recover-link {
      font-size: 0.8rem;
      color: var(--danger);
      text-decoration: none;
    }
    .dir-recover-link:hover { text-decoration: underline; }
    .dir-recover-box {
      margin-top: 0.75rem;
      background: rgba(248, 81, 73, 0.05);
      border: 1px solid rgba(248, 81, 73, 0.25);
      border-radius: 6px;
      padding: 0.75rem 1rem;
    }
    .dir-recover-warning {
      font-size: 0.825rem;
      color: var(--text-dim);
      margin: 0 0 0.75rem;
      line-height: 1.5;
    }
    .btn-danger-outline {
      background: transparent;
      border: 1px solid var(--danger);
      color: var(--danger);
    }
    .btn-danger-outline:hover { background: rgba(248, 81, 73, 0.1); opacity: 1; }
    .dir-key-hint {
      font-size: 0.8rem;
      color: var(--text-dim);
      margin-bottom: 0.5rem;
    }
    .dir-key-hint code {
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
      font-size: 0.78rem;
      color: var(--accent);
      word-break: break-all;
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
    .dir-textarea:focus { border-color: var(--accent); }
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
    .dir-input:focus { border-color: var(--accent); }
    .dir-row {
      display: flex;
      align-items: center;
      gap: 0.75rem;
    }
    .dir-status { font-size: 0.85rem; }
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
    .dir-table thead tr { border-bottom: 1px solid var(--border); }
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
    .row-dup td { background: rgba(255, 166, 0, 0.05); }
    .row-dup:hover td { background: rgba(255, 166, 0, 0.1) !important; }
    .dup-tag {
      font-size: 0.7rem;
      font-weight: 700;
      color: #e3a700;
      background: rgba(255, 166, 0, 0.15);
      border-radius: 3px;
      padding: 0 4px;
      vertical-align: middle;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
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
    .btn-ssh { color: var(--accent); }
    .btn-ssh:hover { text-decoration: underline; }
    .ssh-key-row td { border-top: none !important; }
    .ssh-key-cell { background: var(--surface2); padding: 0.25rem 0.75rem 0.75rem !important; }
    .ssh-key-error { color: var(--danger); font-size: 0.8rem; margin-top: 0.25rem; }
    .ssh-key-ok { color: var(--success, #2a9d5c); font-size: 0.75rem; margin-top: 0.25rem; font-family: monospace; white-space: pre; }
    .dir-groups-desc { font-size: 0.85rem; color: var(--text-dim); margin: 0 0 1rem; line-height: 1.5; }
    .dir-field-error { color: var(--danger); font-size: 0.8rem; margin-top: 0.35rem; }
    .grp-card {
      background: var(--surface2);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 0.85rem 1rem;
      margin-bottom: 0.75rem;
    }
    .grp-header {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      margin-bottom: 0.6rem;
    }
    .grp-name {
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
      font-size: 0.9rem;
      font-weight: 700;
      color: var(--text);
    }
    .grp-gid { font-size: 0.75rem; color: var(--muted); }
    .grp-delete-btn { margin-left: auto; font-size: 0.78rem; }
    .grp-members { display: flex; flex-wrap: wrap; gap: 0.4rem; align-items: center; }
    .grp-member-tag {
      display: inline-flex;
      align-items: center;
      gap: 0.25rem;
      background: rgba(88, 166, 255, 0.12);
      border: 1px solid rgba(88, 166, 255, 0.25);
      border-radius: 4px;
      padding: 0.15rem 0.4rem;
      font-size: 0.8rem;
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
      color: var(--text-dim);
    }
    .grp-member-remove {
      background: none;
      border: none;
      cursor: pointer;
      color: var(--muted);
      font-size: 0.7rem;
      padding: 0;
      font-family: inherit;
      line-height: 1;
    }
    .grp-member-remove:hover { color: var(--danger); }
    .grp-add-select {
      padding: 0.2rem 0.4rem;
      border-radius: 4px;
      border: 1px solid var(--border);
      background: var(--surface);
      color: var(--text);
      font-size: 0.8rem;
      font-family: inherit;
      cursor: pointer;
    }
    .grp-no-users { font-size: 0.8rem; color: var(--muted); font-style: italic; }
    CSS
  end
end
