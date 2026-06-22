#!/usr/bin/env bash
# fnm and nvm are retired from the fleet (2026-06-22); node now comes from the
# mise manifest. Keep this cleanup idempotent so every hourly chezmoi update
# removes leftover installs regardless of how they got there. Mirrors
# run_after_15-remove-opencode.sh.
set -euo pipefail

remove_path() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    rm -rf "$path"
    echo "removed: $path"
  fi
}

# fnm: binary, node-versions cache (often >1GB), shell aliases.
remove_path "$HOME/.local/share/fnm"
remove_path "$HOME/.local/bin/fnm"
# nvm: install dir + node versions.
remove_path "$HOME/.nvm"
