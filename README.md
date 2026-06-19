# fleet-provisioning

Convergent workstation provisioning: bring any machine up to "how I work on
Spark" with one command, across planes — CLI/TUI tools, shell, agent
definitions, and secrets.

This replaced the homegrown trio (`dotfiles/install.sh` push fan-out +
`agent-sync` + the secret materialize helper) with chezmoi as a single
pull-model convergence engine.

## Division of labor

| Plane | Tool | Notes |
|---|---|---|
| User env: dotfiles, CLI/TUI tools, shell, agent defs | **chezmoi** | pull-model, per-machine templating, single-binary bootstrap |
| Secrets | **chezmoi + OpenBao** | rendered at apply from `kv/projects/*`; never in the repo |
| System: Spark serving stack (user systemd units) | **chezmoi** | `dot_config/systemd/user/*.service`, spark-only via `.chezmoiignore`; a `run_after` hook does `daemon-reload` + enable. No root/apt — user-local by design. |

chezmoi is the convergence engine. Dotfiles, nvim, and tool configs now live
**in** chezmoi (migrated stow→chezmoi 2026-06-18); it still drives the hardened
`dotfiles/install.sh` for tool *installs* via a `run_after` script.

## Bootstrap a machine

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
~/.local/bin/chezmoi init --apply https://github.com/fhestvang/fleet-provisioning.git
```

That clones this repo (source is `home/`, see `.chezmoiroot`), computes
per-machine facts (`role`, `isAgentHost`, `baoReachable`), runs the dotfiles
installer for tools, and runs agent-sync on agent hosts. Secrets aren't rendered
— the per-tool wrappers read Bao at call time (see below).

There's no push/control-node step: every box self-converges on an hourly
`chezmoi update` cron (`run_after_02-install-sync-cron`).

## Per-machine facts (`home/.chezmoi.toml.tmpl`)

- `role`: `spark` | `laptop` | `pi` | `tiny`
- `isAgentHost`: spark/laptop get agent-definition sync; tinys do not
- `baoReachable`: whether OpenBao answers from this host

## Secrets

Secrets live in OpenBao (`kv/projects/*`) and **never touch the repo**. Rather
than render secret files, the per-tool wrappers (linear-tui, `scw`) read Bao at
call time on every box, so rotation is just `bao kv patch …`.

Bao-on-fleet is **resolved** (2026-06-17): a Tailscale ACL grant plus a per-box
scoped read-only AppRole token in `~/.vault-token` (refreshed by `bao-relogin`)
let every machine reach Bao, so the old `dotfiles-fleet-linear-key` materialize
was retired. `.chezmoi.toml.tmpl` still computes `baoReachable` per host. See
`docs/architecture.md` for the full account.

## Status

chezmoi is the **live** manager across the fleet (spark + eigil + dicte + pi3 +
laptop), converging via the hourly `chezmoi-sync` cron; only ingvild is held back
for a hands-on `chezmoi init` session. The old `dotfiles` commit-hook fan-out is
**retired** (hook + `dotfiles-fleet-sync` deleted). See `docs/architecture.md`
for the full migration log.
