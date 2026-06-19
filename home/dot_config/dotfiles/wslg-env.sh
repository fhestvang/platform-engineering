# shellcheck shell=bash  # sourced fragment, no shebang
# WSLg sometimes starts shells/tmux without GUI environment variables.
# Keep clipboard and desktop integrations pointed at the Linux session.
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && [ -S /mnt/wslg/.X11-unix/X0 ]; then
  export DISPLAY="${DISPLAY:-:0}"

  if [ -S "/run/user/$(id -u)/wayland-0" ]; then
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
  elif [ -S /mnt/wslg/runtime-dir/wayland-0 ]; then
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/mnt/wslg/runtime-dir}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
  fi

  if [ -S /mnt/wslg/PulseServer ]; then
    export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"
  fi
fi
