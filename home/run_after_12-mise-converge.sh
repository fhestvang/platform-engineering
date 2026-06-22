#!/usr/bin/env bash
# Converge the mise manifest. chezmoi owns ~/.config/mise/config.toml; this
# makes the installed toolset match it. Runs after run_after_10 has installed
# the mise binary. Idempotent + safe on every hourly chezmoi update.
#   mise install  -> install everything declared (pinned + first agent pull)
#   mise upgrade  -> float `latest` specs up (agents/utility CLIs); exact pins
#                    (node/neovim/go/lazygit) stay put, so nvim never silently
#                    breaks LazyVim again.
set -uo pipefail

export PATH="$HOME/.local/bin:$PATH"
export MISE_YES=1

command -v mise >/dev/null 2>&1 || { echo "mise-converge: mise not on PATH yet, skipping"; exit 0; }
[ -f "$HOME/.config/mise/config.toml" ] || { echo "mise-converge: no manifest yet, skipping"; exit 0; }

mise install || echo "mise-converge: install reported errors (continuing)"
mise upgrade || echo "mise-converge: upgrade reported errors (continuing)"
mise reshim || true
echo "mise-converge: done"
