# fleet-provisioning

Convergent workstation provisioning: bring any machine up to "how I work on
Spark" with one command, across planes — CLI/TUI tools, shell, agent
definitions, and secrets.

This replaces the homegrown trio (`dotfiles/install.sh` push fan-out +
`agent-sync` + the secret materialize helper) with two composable, off-the-shelf
tools.

## Division of labor

| Plane | Tool | Notes |
|---|---|---|
| User env: dotfiles, CLI/TUI tools, shell, agent defs | **chezmoi** | pull-model, per-machine templating, single-binary bootstrap |
| Secrets | **chezmoi + OpenBao** | rendered at apply from `kv/projects/*`; never in the repo |
| System: packages (sudo), systemd services, users | **Ansible** | `ansible/` — system role is a stub for now |
| Fleet orchestration + VPC discovery | **Ansible** | static `hosts.ini` (pets) + `scaleway.yml` dynamic inventory (cattle) |

chezmoi is the convergence engine; for now it **drives the hardened
`dotfiles/install.sh`** (tools/stow/plugins) via a `run_onchange` script rather
than re-porting its content — so nothing that already works breaks. Content can
migrate into chezmoi incrementally later.

## Bootstrap a machine

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
~/.local/bin/chezmoi init --apply https://github.com/fhestvang/fleet-provisioning.git
```

That clones this repo (source is `home/`, see `.chezmoiroot`), computes
per-machine facts (`role`, `isAgentHost`, `baoReachable`), clones+runs the
dotfiles installer, runs agent-sync on agent hosts, and renders secrets where
OpenBao is reachable.

Across the fleet from a control node:

```sh
cd ansible && ansible-playbook site.yml
```

## Per-machine facts (`home/.chezmoi.toml.tmpl`)

- `role`: `spark` | `laptop` | `pi` | `tiny`
- `isAgentHost`: spark/laptop get agent-definition sync; tinys do not
- `baoReachable`: whether OpenBao answers from this host

## Secrets

Secrets live in OpenBao (`kv/projects/*`) and are rendered at apply time — e.g.
`home/private_dot_config/linear-tui/env.tmpl` pulls `kv/projects/linear`. The
rendered file is `0600` (`private_` prefix) and is `.gitignore`d.

**Known blocker:** OpenBao is reachable from Spark but **not from the fleet**
(TLS/CA trust or the port-less proxy). So `baoReachable` is false on the tinys,
and `.chezmoiignore` skips the secret file there — the existing
`dotfiles-fleet-linear-key` materialize stays the fleet path until Bao-on-fleet
(CA trust + per-machine AppRole) is solved. That same work unblocks Ansible
`hashi_vault` lookups and the VPC plan.

## Coexistence & cutover (transition state)

- The current `dotfiles` commit-hook fan-out is **still live and untouched**.
  Both it and chezmoi's run script call `install.sh`, so they don't fight; they
  just both keep tooling fresh.
- Per-box cutover = run `chezmoi init --apply` there, then disable the fan-out
  for that box. Do this deliberately, one box at a time, after verifying parity.
- Nothing here has been applied to a live home yet — see `docs/architecture.md`
  for status and the staged plan.
