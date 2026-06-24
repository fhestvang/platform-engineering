# Shared interactive shell configuration for Bash and Zsh.
# shellcheck shell=bash  # sourced file; lint as bash (shellcheck has no zsh mode)

# Fall back to C.UTF-8 when the inherited locale isn't generated on this host.
# Minimal cloud images and Raspberry Pi OS often lack en_US.UTF-8, which the SSH
# client forwards via LC_*; that makes every tool warn "cannot change locale".
# C.UTF-8 is built into glibc, so this needs no locale-gen or sudo, and it only
# triggers when the active locale is actually broken (so Spark/laptop keep
# theirs). Note: this fixes child processes and the rest of the session, not the
# login-shell banner — that needs a valid locale in the env before login (see
# the SSH SetEnv approach for fleet hosts).
if command -v locale >/dev/null 2>&1 && locale 2>&1 | grep -qiE 'cannot (set|change) locale'; then
  unset LANGUAGE LC_CTYPE LC_MESSAGES LC_COLLATE LC_NUMERIC LC_TIME LC_MONETARY LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION
  export LANG=C.UTF-8 LC_ALL=C.UTF-8
fi

if [ -r "$HOME/.config/dotfiles/wslg-env.sh" ]; then
  . "$HOME/.config/dotfiles/wslg-env.sh"
fi

DOTFILES_MACHINE="$("$HOME/.local/bin/prompt-host" 2>/dev/null || hostname -s 2>/dev/null || printf local)"
export DOTFILES_MACHINE

# Headroom ships anonymous usage telemetry ON by default; opt out for every
# invocation (CLI, `headroom wrap`, the MCP server spawned by an agent launched
# from this shell). The systemd proxy sets this in its own env file as well.
export HEADROOM_TELEMETRY=off
export DAGGER_NO_NAG=1

# OpenBao endpoint — the host-independent Tailscale Service name (reachable from
# every box once the tailnet ACL grants it). Lets bao/vkv and the scw/linear
# wrappers find Bao without each caller hardcoding the address.
export BAO_ADDR="${BAO_ADDR:-https://bao.olm-hops.ts.net}"

dotfiles_is_spark() {
  [ "$DOTFILES_MACHINE" = "spark" ]
}

dotfiles_spark_command() {
  local command_prefix="$1"
  shift
  local quoted="" arg

  for arg in "$@"; do
    quoted+=" $(printf '%q' "$arg")"
  done

  # shellcheck disable=SC2033  # 'spark' is the ssh Host alias, not the spark() function
  if [ -t 0 ] && [ -t 1 ]; then
    ssh -o ClearAllForwardings=yes -t spark "$command_prefix$quoted"
  else
    ssh -o ClearAllForwardings=yes spark "$command_prefix$quoted"
  fi
}

dotfiles_path_prepend() {
  [ -d "$1" ] || return
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

dotfiles_path_prepend "$HOME/.local/bin"
dotfiles_path_prepend "$HOME/bin"
dotfiles_path_prepend "$HOME/.cargo/bin"
dotfiles_path_prepend "$HOME/.local/share/fzf/bin"
export PATH

dotfiles_refresh_linux_path() {
  local rest dir filtered

  rest="$PATH:"
  filtered=""
  while [ -n "$rest" ]; do
    dir="${rest%%:*}"
    rest="${rest#*:}"
    case "$dir" in
      /mnt/[a-zA-Z]/*) continue ;;
    esac
    filtered="${filtered:+$filtered:}$dir"
  done

  DOTFILES_LINUX_PATH="$filtered"
}

dotfiles_have_linux() {
  local rest dir candidate

  if [ -z "${DOTFILES_LINUX_PATH:-}" ]; then
    dotfiles_refresh_linux_path
  fi

  case "$1" in
    */*) [ -x "$1" ] && [ ! -d "$1" ]; return ;;
  esac

  rest="$DOTFILES_LINUX_PATH:"
  while [ -n "$rest" ]; do
    dir="${rest%%:*}"
    rest="${rest#*:}"
    [ -n "$dir" ] || dir=.
    candidate="$dir/$1"
    if [ -x "$candidate" ] && [ ! -d "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

alias ll='ls -alF'
alias la='ls -A'
alias cc='claude --continue'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias gs='git status'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias gba='git branch -a'
alias ga='git add -p'
alias gpl='git pull --ff-only'
alias gps='git push'
alias glog="git log --graph --topo-order --pretty='%C(yellow)%h%Creset %C(cyan)%ar%Creset %C(green)%an%Creset %C(auto)%d%Creset %s' --abbrev-commit"

whereami() {
  printf '%s\n' "$DOTFILES_MACHINE"
}

dotfiles_tmux_client_session() {
  # One plain session per base name, shared by every terminal. No per-tty
  # grouped sessions: grouping let sibling sessions diverge on current-window,
  # which (with focus-events) made Win+Shift+S screenshot the wrong window.
  local base="${1:-main}"

  tmux has-session -t "$base" 2>/dev/null || tmux new-session -d -s "$base"
  printf '%s\n' "$base"
}

dotfiles_tmux_base_sessions() {
  tmux list-sessions -F '#{session_name}	#{session_group}' |
    awk '
      {
        name=$1
        group=$2
        base=(group == "" ? name : group)
        if (!seen[base]++) print base
      }
    '
}

t() {
  local target_session

  target_session="$(dotfiles_tmux_client_session main)"
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$target_session"
  else
    # no exec: detaching tmux returns to this spark shell instead of closing
    # the SSH session and dropping all the way back to the laptop.
    tmux -2 attach-session -t "$target_session"
  fi
}

__dotfiles_wezterm_set_user_var() {
  # Emit when we can see WezTerm directly, or when inside tmux: tmux overrides
  # TERM_PROGRAM=tmux and strips WEZTERM_PANE over SSH, so the only reliable
  # signal from a remote tmux pane is $TMUX. The passthrough form below reaches
  # the outer WezTerm and is a no-op in terminals that don't grok OSC 1337.
  [ "${TERM_PROGRAM:-}" = "WezTerm" ] || [ -n "${WEZTERM_PANE:-}" ] || [ -n "${TMUX:-}" ] || return 0
  dotfiles_have_linux base64 || return 0

  local name="$1"
  local value="$2"
  local encoded

  encoded="$(printf '%s' "$value" | base64 | tr -d '\r\n')"
  if [ -n "${TMUX:-}" ]; then
    printf '\033Ptmux;\033\033]1337;SetUserVar=%s=%s\a\033\\' "$name" "$encoded"
  else
    printf '\033]1337;SetUserVar=%s=%s\a' "$name" "$encoded"
  fi
}

__dotfiles_machine_ip() {
  if [ -n "${DOTFILES_MACHINE_IP:-}" ]; then
    printf '%s' "$DOTFILES_MACHINE_IP"
    return 0
  fi

  local ip windows_tailscale

  if dotfiles_have_linux tailscale; then
    ip="$(tailscale ip -4 2>/dev/null | awk 'NR == 1 { print; exit }')" || ip=""
  fi

  if [ -z "$ip" ]; then
    windows_tailscale="/mnt/c/Program Files/Tailscale/tailscale.exe"
    if [ -x "$windows_tailscale" ]; then
      ip="$("$windows_tailscale" ip -4 2>/dev/null | tr -d '\r' | awk 'NR == 1 { print; exit }')" || ip=""
    fi
  fi

  if [ -z "$ip" ]; then
    ip="$(hostname -I 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i !~ /^(127\.|169\.254\.|fe80:|::1$)/) { print $i; exit } }')" || ip=""
  fi

  DOTFILES_MACHINE_IP="$ip"
  export DOTFILES_MACHINE_IP
  printf '%s' "$DOTFILES_MACHINE_IP"
}

__dotfiles_update_wezterm_context() {
  local image_paste_host machine_ip

  # Stamp the image-paste host as the machine this prompt runs on, so a pasted
  # screenshot lands where the agent reading it actually runs: laptop shells keep
  # pastes local, spark shells upload to spark. Agents now run on both machines,
  # so the old blanket 'spark' target (2026-06-12) misrouted laptop pastes. This
  # runs every prompt, so moving between machines (e.g. `ts` into spark and back)
  # re-stamps the pane and never leaves a stale host. Override per-shell with
  # CODEX_IMAGE_PASTE_HOST to force a different target.
  image_paste_host="${CODEX_IMAGE_PASTE_HOST:-$DOTFILES_MACHINE}"
  machine_ip="$(__dotfiles_machine_ip)"

  __dotfiles_wezterm_set_user_var FHH_HOST "$DOTFILES_MACHINE"
  __dotfiles_wezterm_set_user_var FHH_HOST_ADDR "$machine_ip"
  __dotfiles_wezterm_set_user_var FHH_IMAGE_PASTE_HOST "$image_paste_host"
}

spark() {
  if dotfiles_is_spark; then
    printf 'already on spark\n'
  else
    ssh -t spark
  fi
}

ts() {
  local remote_command ssh_command tty_stdio=false

  # no exec on tmux: after detach, fall through to a spark login shell rather
  # than ending the SSH command and bouncing back to the laptop.
  remote_command='printf "\033]1337;SetUserVar=FHH_HOST=c3Bhcms=\a"; if command -v tailscale >/dev/null 2>&1 && command -v base64 >/dev/null 2>&1; then addr="$(tailscale ip -4 2>/dev/null | sed -n 1p)"; if [ -n "$addr" ]; then addr_b64="$(printf "%s" "$addr" | base64 | tr -d "\r\n")"; printf "\033]1337;SetUserVar=FHH_HOST_ADDR=%s\a" "$addr_b64"; fi; fi; printf "\033]1337;SetUserVar=FHH_IMAGE_PASTE_HOST=c3Bhcms=\a"; export PATH="$HOME/.local/bin:$HOME/bin:$PATH"; export TERM=xterm-256color; shell="$(command -v zsh 2>/dev/null || command -v bash 2>/dev/null || printf /bin/sh)"; export SHELL="$shell"; tmux -2 new-session -A -s main; exec "$shell" -l'
  if { : < /dev/tty > /dev/tty; } 2>/dev/null; then
    tty_stdio=true
  fi

  if dotfiles_is_spark; then
    t
  elif [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    __dotfiles_wezterm_set_user_var FHH_HOST spark
    __dotfiles_wezterm_set_user_var FHH_IMAGE_PASTE_HOST spark
    ssh_command="ssh -tt -o ClearAllForwardings=yes spark $(printf '%q' "$remote_command")"
    if [ "$tty_stdio" = true ]; then
      ssh_command="$ssh_command </dev/tty >/dev/tty 2>&1"
    fi
    tmux detach-client -E "$ssh_command"
  else
    __dotfiles_wezterm_set_user_var FHH_HOST spark
    __dotfiles_wezterm_set_user_var FHH_IMAGE_PASTE_HOST spark
    # shellcheck disable=SC2033  # 'spark' is the ssh Host alias, not the spark() function
    if [ "$tty_stdio" = true ]; then
      ssh -tt -o ClearAllForwardings=yes spark "$remote_command" < /dev/tty > /dev/tty 2>&1
    else
      ssh -tt -o ClearAllForwardings=yes spark "$remote_command"
    fi
  fi
}

tsp() {
  local base target_session

  if [ -n "${TMUX:-}" ]; then
    if dotfiles_have_linux fzf; then
      tmux display-popup -E -w 88% -h 78% -d "#{pane_current_path}" -T "tmux sessions" \
        'session="$(tmux list-sessions -F "#{session_name}" | fzf --prompt="tmux session> " --height=100% --layout=reverse --border=none)" || exit; [ -n "$session" ] || exit; tmux switch-client -t "$session"'
    else
      tmux display-message 'tsp: install fzf for session switching'
    fi
  else
    if dotfiles_have_linux fzf; then
      base="$(dotfiles_tmux_base_sessions | fzf --prompt='tmux session> ' --height=100% --layout=reverse --border=none)" || return
      [ -n "$base" ] || return
    else
      base=main
    fi
    target_session="$(dotfiles_tmux_client_session "$base")"
    # no exec: detaching tmux returns to this spark shell instead of closing
    # the SSH session and dropping all the way back to the laptop.
    tmux -2 attach-session -t "$target_session"
  fi
}

laptop() {
  if dotfiles_is_spark; then
    if [ -n "${TMUX:-}" ] && [ -n "${SSH_CONNECTION:-}" ]; then
      tmux detach-client -P
    elif [ -n "${TMUX:-}" ]; then
      tmux detach-client
    elif [ -n "${SSH_CONNECTION:-}" ]; then
      exit
    else
      printf 'already on spark, but not inside tmux or ssh\n'
    fi
  else
    printf 'already on laptop/local machine\n'
  fi
}

# linear-tui: inject the Linear API key at launch (never stored on disk),
# mirroring the scw-from-Bao pattern. Order: an already-exported LINEAR_API_KEY
# wins; else read it from OpenBao (kv/projects/linear, field api_key); else a
# materialized ~/.config/linear-tui/env; else a clear error. This is what makes
# "push to the Idea Vault from any box" work wherever Bao or the env file reach.
if command -v linear-tui >/dev/null 2>&1; then
  linear-tui() {
    local key="${LINEAR_API_KEY:-}"
    if [ -z "$key" ] && command -v bao >/dev/null 2>&1; then
      key="$(bao kv get -field=api_key kv/projects/linear 2>/dev/null || true)"
    fi
    if [ -z "$key" ] && [ -r "$HOME/.config/linear-tui/env" ]; then
      key="$(. "$HOME/.config/linear-tui/env" 2>/dev/null; printf '%s' "${LINEAR_API_KEY:-}")"
    fi
    if [ -z "$key" ]; then
      printf 'linear-tui: no LINEAR_API_KEY (Bao kv/projects/linear unreachable and no ~/.config/linear-tui/env)\n' >&2
      return 1
    fi
    LINEAR_API_KEY="$key" command linear-tui "$@"
  }
fi

# vkv: recursive OpenBao/Vault KV browser + search (what the Bao web UI can't do
# — it only prefix-searches one level). Point it at Bao; it reads the token from
# ~/.vault-token. Examples: `vkv export -p kv`  /  `vkv export -p kv --only-keys`.
if command -v vkv >/dev/null 2>&1; then
  vkv() { VAULT_ADDR="${BAO_ADDR:-https://bao.olm-hops.ts.net}" VKV_DISABLE_WARNING=true command vkv "$@"; }
fi

if dotfiles_have_linux eza; then
  alias ls='eza -l --icons --no-permissions --no-user --total-size --sort=size'
  alias l='eza -l --icons --git -a'
  alias lt='eza --tree --level=2 --long --icons --git'
else
  alias l='ls -CF'
fi

if dotfiles_have_linux batcat; then
  alias cat='batcat'
elif dotfiles_have_linux bat; then
  alias cat='bat'
fi

if dotfiles_have_linux kubectl; then
  alias k='kubectl'
  alias kg='kubectl get'
  alias kd='kubectl describe'
  alias kl='kubectl logs -f'
  alias ke='kubectl exec -it'
  alias kcns='kubectl config set-context --current --namespace'
fi

if command -v docker >/dev/null 2>&1; then
  alias dco='docker compose'
  alias dps='docker ps'
  alias dpa='docker ps -a'
  alias di='docker images'
  alias dx='docker exec -it'
  alias dlf='docker logs -f'
  alias dcup='docker compose up'
  alias dcupb='docker compose up --build'
  alias dcdn='docker compose down'
  alias dcl='docker compose logs -f'
fi

if dotfiles_have_linux lazydocker; then
  alias lzd='lazydocker'
fi

if [ -r "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi

# Node and other runtimes come from mise (see ~/.config/mise/config.toml).
# nvm and fnm were retired 2026-06-22 in favour of a single mise manifest so
# node/agent versions stay aligned fleet-wide instead of drifting per machine.

if dotfiles_have_linux mise; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(mise activate zsh)"
  else
    eval "$(mise activate bash)"
  fi
  dotfiles_refresh_linux_path
fi

if [ -n "${BASH_VERSION:-}" ] && [ -r "$HOME/.openclaw/completions/openclaw.bash" ]; then
  . "$HOME/.openclaw/completions/openclaw.bash"
fi

__dotfiles_refresh_tmux_display_env() {
  [ -n "${TMUX:-}" ] || return 0
  dotfiles_have_linux tmux || return 0
  eval "$(
    for name in DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS XDG_CURRENT_DESKTOP XDG_SESSION_TYPE; do
      tmux show-environment -s "$name" 2>/dev/null | sed '/^-/d'
    done
  )"
}

if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd __dotfiles_refresh_tmux_display_env
  add-zsh-hook precmd __dotfiles_update_wezterm_context
elif [ -n "${BASH_VERSION:-}" ]; then
  case ";${PROMPT_COMMAND:-};" in
    *";__dotfiles_update_wezterm_context;"*) ;;
    *) PROMPT_COMMAND="__dotfiles_update_wezterm_context${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
  esac
fi

if dotfiles_have_linux zoxide; then
  # Silence the zoxide doctor: it warns because starship/mise/syntax-highlight
  # register their hooks after zoxide, so it thinks it is not "last". For a
  # chpwd-based dir tracker that ordering is harmless, and the nag prints on
  # every non-interactive shell startup. See https://github.com/ajeetdsouza/zoxide#installation
  export _ZO_DOCTOR=0
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(zoxide init zsh --cmd cd)"
  else
    eval "$(zoxide init bash --cmd cd)"
  fi
fi

if dotfiles_have_linux yazi; then
  y() {
    local tmp cwd
    tmp="$(mktemp -t yazi-cwd.XXXXXX)" || return
    yazi "$@" --cwd-file="$tmp"
    cwd="$(cat "$tmp" 2>/dev/null)"
    rm -f "$tmp"
    [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && { builtin cd -- "$cwd" || return; }
  }
fi

if dotfiles_have_linux fd; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
elif dotfiles_have_linux fdfind; then
  export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
fi

if dotfiles_have_linux fzf; then
  if [ -n "${BASH_VERSION:-}" ]; then
    [ -r /usr/share/doc/fzf/examples/key-bindings.bash ] && . /usr/share/doc/fzf/examples/key-bindings.bash
    [ -r /usr/share/doc/fzf/examples/completion.bash ] && . /usr/share/doc/fzf/examples/completion.bash
    [ -r "$HOME/.local/share/fzf/shell/key-bindings.bash" ] && . "$HOME/.local/share/fzf/shell/key-bindings.bash"
    [ -r "$HOME/.local/share/fzf/shell/completion.bash" ] && . "$HOME/.local/share/fzf/shell/completion.bash"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    if zle >/dev/null 2>&1; then
      [ -r /usr/share/doc/fzf/examples/key-bindings.zsh ] && . /usr/share/doc/fzf/examples/key-bindings.zsh
      [ -r /usr/share/doc/fzf/examples/completion.zsh ] && . /usr/share/doc/fzf/examples/completion.zsh
      [ -r "$HOME/.local/share/fzf/shell/key-bindings.zsh" ] && . "$HOME/.local/share/fzf/shell/key-bindings.zsh"
      [ -r "$HOME/.local/share/fzf/shell/completion.zsh" ] && . "$HOME/.local/share/fzf/shell/completion.zsh"
    fi
  fi
fi

if dotfiles_have_linux atuin; then
  # --disable-up-arrow: keep the up-arrow as the vi prefix-search bound in
  # .zshrc. --disable-ai: leave `?` as vim reverse-search, not atuin AI.
  # atuin takes Ctrl-R, rebound after fzf in .zshrc (fzf also grabs Ctrl-R).
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(atuin init zsh --disable-up-arrow --disable-ai)"
  else
    eval "$(atuin init bash --disable-up-arrow --disable-ai)"
  fi
fi

if dotfiles_have_linux direnv; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(direnv hook zsh)"
  else
    eval "$(direnv hook bash)"
  fi
fi

# OpenBao GitHub-CLI env: cached because the synchronous Bao round-trip
# (AppRole login + KV read) over Tailscale adds ~0.5s to every interactive
# shell startup on the laptop. We source the cached env file instantly and
# refresh in the background when it's missing or older than 12h.
dotfiles_openbao_env_script=""
for dotfiles_openbao_env_candidate in \
  "$HOME/github/fos/platform/openbao/openbao-github-cli-shell-env.sh" \
  "$HOME/github/fos/infrastructure/openbao-github-cli-shell-env.sh"; do
  if [ -x "$dotfiles_openbao_env_candidate" ]; then
    dotfiles_openbao_env_script="$dotfiles_openbao_env_candidate"
    break
  fi
done
unset dotfiles_openbao_env_candidate

if [ -n "$dotfiles_openbao_env_script" ]; then
  dotfiles_openbao_env_cache="${XDG_CACHE_HOME:-$HOME/.cache}/fos/openbao-github-token.env"
  # shellcheck source=/dev/null  # runtime cache path, not present at lint time
  [ -r "$dotfiles_openbao_env_cache" ] && . "$dotfiles_openbao_env_cache"
  if [ ! -r "$dotfiles_openbao_env_cache" ] || \
     [ -n "$(find "$dotfiles_openbao_env_cache" -mmin +720 2>/dev/null)" ]; then
    (
      mkdir -p "$(dirname "$dotfiles_openbao_env_cache")" 2>/dev/null
      tmp="$(mktemp "${dotfiles_openbao_env_cache}.XXXXXX" 2>/dev/null)" || exit 0
      chmod 600 "$tmp" 2>/dev/null
      if "$dotfiles_openbao_env_script" >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        mv "$tmp" "$dotfiles_openbao_env_cache"
      else
        rm -f "$tmp"
      fi
    ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
  unset dotfiles_openbao_env_cache
fi
unset dotfiles_openbao_env_script

hermes() {
  if dotfiles_is_spark; then
    command hermes "$@"
  else
    dotfiles_spark_command "export PATH=\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH; hermes" "$@"
  fi
}

agent-plan() {
  command agent-plan "$@"
}

agent-fast() {
  command agent-fast "$@"
}

agent-private() {
  command agent-private "$@"
}

gc() {
  if dotfiles_is_spark; then
    (cd "$HOME/gc" 2>/dev/null || cd "$HOME" || exit; command gc "$@")
  else
    dotfiles_spark_command "export PATH=\$HOME/opt/go/bin:\$HOME/go/bin:\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH; cd ~/gc 2>/dev/null || cd ~; gc" "$@"
  fi
}

gt() {
  if dotfiles_is_spark; then
    command gt "$@"
  else
    dotfiles_spark_command "export PATH=\$HOME/.local/bin:\$PATH; gt" "$@"
  fi
}

bd() {
  if dotfiles_is_spark; then
    command bd "$@"
  else
    dotfiles_spark_command "export PATH=\$HOME/.local/bin:\$PATH; bd" "$@"
  fi
}

if dotfiles_have_linux starship && [ "${TERM:-dumb}" != "dumb" ]; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    zmodload zsh/parameter 2>/dev/null || true

    if [[ "${widgets[zle-keymap-select]-}" == user:starship_zle-keymap-select-wrapped ]]; then
      case "${__starship_preserved_zle_keymap_select-}" in
        ""|starship_zle-keymap-select|starship_zle-keymap-select-wrapped)
          zle -N zle-keymap-select starship_zle-keymap-select 2>/dev/null || true
          unset __starship_preserved_zle_keymap_select
          ;;
      esac
    fi

    if [[ "${widgets[zle-keymap-select]-}" == user:starship_zle-keymap-select ||
      "${widgets[zle-keymap-select]-}" == user:starship_zle-keymap-select-wrapped ]]; then
      DOTFILES_STARSHIP_ZSH_INITIALIZED=1
    fi

    if [ -z "${DOTFILES_STARSHIP_ZSH_INITIALIZED:-}" ]; then
      DOTFILES_STARSHIP_ZSH_INITIALIZED=1
      eval "$(starship init zsh)"
    fi
  else
    if [ -z "${DOTFILES_STARSHIP_BASH_INITIALIZED:-}" ]; then
      DOTFILES_STARSHIP_BASH_INITIALIZED=1
      eval "$(starship init bash)"
    fi
  fi
fi
