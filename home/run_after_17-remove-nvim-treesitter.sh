#!/usr/bin/env bash
# Treesitter is retired from the fleet Neovim baseline. Keep this cleanup
# idempotent so every hourly chezmoi update removes old Lazy/Mason installs and
# generated parser state regardless of which machine installed them.
set -euo pipefail

remove_path() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    rm -rf "$path"
    echo "removed: $path"
  fi
}

remove_path "$HOME/.local/share/nvim/lazy/nvim-treesitter"
remove_path "$HOME/.local/share/nvim/lazy/nvim-treesitter-textobjects"
remove_path "$HOME/.local/share/nvim/lazy/nvim-ts-autotag"
remove_path "$HOME/.local/share/nvim/lazy/ts-comments.nvim"

remove_path "$HOME/.local/share/nvim/mason/bin/tree-sitter"
remove_path "$HOME/.local/share/nvim/mason/packages/tree-sitter-cli"

remove_path "$HOME/.local/share/nvim/site/parser"
remove_path "$HOME/.local/share/nvim/site/queries"
