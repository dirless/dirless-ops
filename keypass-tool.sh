#!/bin/bash
# Manage KeePassXC master password in the Linux kernel keyring.
#
# Stores in the session keyring (@s) so child processes (Ansible, scripts)
# inherit it automatically without needing uid-based permission changes.
#
# Usage:
#   keypass-tool.sh          — print master password (for scripts/Ansible)
#   keypass-tool.sh unlock   — prompt and store password in keyring

_KEY_ID_FILE="${XDG_RUNTIME_DIR:-$HOME/.cache}/.kp-id"

if [[ "${1}" == "unlock" ]]; then
  read -rs -p "KeePassXC master password: " pw
  echo
  if ! printf '%s\n' "$pw" | keepassxc-cli ls "$HOME/Dropbox/Dirless/DirlessPasswords.kdbx" > /dev/null 2>&1; then
    echo "Error: incorrect password or database not found" >&2
    exit 1
  fi
  old=$(cat "$_KEY_ID_FILE" 2>/dev/null) && keyctl unlink "$old" @s 2>/dev/null || true
  key_id=$(echo -n "$pw" | keyctl padd user keepassxc-master @s)
  echo "$key_id" > "$_KEY_ID_FILE"
  chmod 600 "$_KEY_ID_FILE"
  echo "Stored in kernel keyring (session). Clears on logout/reboot."
  echo "To clear manually: keyctl unlink \$(cat $_KEY_ID_FILE) @s && rm $_KEY_ID_FILE"
else
  key_id=$(cat "$_KEY_ID_FILE" 2>/dev/null) || {
    echo "KeePassXC master not in keyring — run: keypass-tool.sh unlock" >&2
    exit 1
  }
  keyctl pipe "$key_id" 2>/dev/null || {
    echo "KeePassXC master not in keyring — run: keypass-tool.sh unlock" >&2
    exit 1
  }
fi
