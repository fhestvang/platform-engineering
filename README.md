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

For a Scaleway instance, use the OpenTofu/cloud-init path:

```sh
just scw-instance-init
just scw-instance-plan scw-agent-02
just scw-instance-apply scw-agent-02
just scw-instance-verify scw-agent-02
```

It creates a one-use `tag:scw-agent` Tailscale auth key, renders cloud-init
user-data, provisions fleet Bao AppRole material, runs chezmoi on first boot,
and verifies `mise` + the agent harnesses. See `docs/scw-instance-bootstrap.md`
and `provisioning/scw-instance/`.

For a normal manually-enrolled machine:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
~/.local/bin/chezmoi init --apply https://github.com/fhestvang/fleet-provisioning.git
```

That clones this repo (source is `home/`, see `.chezmoiroot`), computes
stable per-machine facts (`role`, `isAgentHost`), runs the dotfiles installer
for tools, and runs agent-sync on agent hosts. Secrets aren't rendered — the
per-tool wrappers read Bao at call time (see below).

There's no push/control-node step: every box self-converges on an hourly
`chezmoi update` cron (`run_after_02-install-sync-cron`).

## Host resource model

- `root`: bootstrap and break-glass only. Do not expect `mise`, agent commands,
  dotfiles, Bao wrappers, or `fhh-toolkit` in `/root`.
- `fhestvang`: the normal working user. This is where chezmoi, mise shims, Bao
  wrappers, shell config, and agent runtime config live.
- `ansible`: legacy/admin user on the tinys. Use it for cluster/system repair
  when needed, not as the day-to-day environment.
- Bao access is a fleet baseline. Tinys need it for wrappers, Atuin, and
  convergence, but Bao access does not make a host an agent host.
- `fhh-toolkit` is agent-host only. It is expected on Spark, laptop, Ingvild,
  and `scw-agent-*`; it is intentionally absent on ordinary `tiny` hosts like
  eigil and dicte.

## Per-machine facts (`home/.chezmoi.toml.tmpl`)

- `role`: `spark` | `laptop` | `pi` | `ingvild` | `scw-agent` | `tiny`
- `isAgentHost`: spark/laptop/ingvild/`scw-*` hosts get agent-definition sync; tinys do not

## Secrets

Secrets live in OpenBao (`kv/projects/*`) and **never touch the repo**. Rather
than render secret files, the per-tool wrappers (linear-tui, `scw`) read Bao at
call time on every box, so rotation is just `bao kv patch …`.

Bao-on-fleet is **resolved** (2026-06-17): a Tailscale ACL grant plus a per-box
scoped read-only AppRole token in `~/.vault-token` (refreshed by `bao-relogin`)
let every machine reach Bao, so the old `dotfiles-fleet-linear-key` materialize
was retired. See `docs/architecture.md` for the full account.

## Status

chezmoi is the **live** manager across the fleet (spark + eigil + ingvild +
dicte + pi3 + laptop), converging via the hourly `chezmoi-sync` cron. The old
`dotfiles` commit-hook fan-out is **retired** (hook + `dotfiles-fleet-sync`
deleted). See `docs/architecture.md` for the full migration log.
