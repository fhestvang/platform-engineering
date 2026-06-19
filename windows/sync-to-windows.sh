#!/usr/bin/env bash
# Sync the Windows-side window-manager configs (GlazeWM + YASB) tracked in this
# repo to the live Windows locations the apps read. These are standalone COPIES,
# not symlinks: the WSL<->Windows boundary plus Developer Mode being off make a
# symlink across /mnt/c unsafe (it would point at an unreachable path).
#
# Run in WSL on the Windows laptop:
#   ./sync-to-windows.sh          push repo -> Windows (default), then reload YASB
#   ./sync-to-windows.sh --pull   capture live edits Windows -> repo
#
# GlazeWM runs elevated, so this script can't reload it: press Alt+Shift+R after
# a push to apply its config. YASB is reloaded automatically.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

command -v cmd.exe >/dev/null 2>&1 || {
  echo "must run in WSL on the Windows laptop (cmd.exe not found)" >&2
  exit 1
}

win_userprofile="$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')"
win_home="$(wslpath "$win_userprofile")"

# repo-relative path : path relative to %USERPROFILE% on Windows
map=(
  "glazewm/config.yaml:.glzr/glazewm/config.yaml"
  "yasb/config.yaml:.config/yasb/config.yaml"
  "yasb/styles.css:.config/yasb/styles.css"
  "flowlauncher/FHH Mono.xaml:AppData/Roaming/FlowLauncher/Themes/FHH Mono.xaml"
  "youtube-music/fhh-mono.css:AppData/Roaming/YouTube Music/themes/fhh-mono.css"
)

mode="push"
[ "${1:-}" = "--pull" ] && mode="pull"

for pair in "${map[@]}"; do
  repo_file="$here/${pair%%:*}"
  win_file="$win_home/${pair##*:}"
  if [ "$mode" = "pull" ]; then
    [ -f "$win_file" ] || { echo "skip (no live file): $win_file" >&2; continue; }
    mkdir -p "$(dirname "$repo_file")"
    cp "$win_file" "$repo_file"
    echo "pulled: $win_file"
  else
    [ -f "$repo_file" ] || { echo "missing repo file: $repo_file" >&2; exit 1; }
    mkdir -p "$(dirname "$win_file")"
    if [ -f "$win_file" ] && ! cmp -s "$repo_file" "$win_file"; then
      cp "$win_file" "$win_file.bak-$(date +%Y%m%d-%H%M%S)"
    fi
    cp "$repo_file" "$win_file"
    echo "pushed: ${pair##*:}"
  fi
done

if [ "$mode" = "push" ]; then
  yasbc="/mnt/c/Program Files/YASB/yasbc.exe"
  if [ -x "$yasbc" ]; then "$yasbc" reload >/dev/null 2>&1 && echo "YASB reloaded"; fi
  echo "GlazeWM is elevated: press Alt+Shift+R to apply its config."
fi
