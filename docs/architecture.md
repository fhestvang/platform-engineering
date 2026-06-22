# Architecture & migration status

## Why

The fleet (Spark + eigil/ingvild/dicte/pi3 + future Scaleway VPCs) was converging
via three hand-rolled mechanisms:

1. `dotfiles/install.sh` + a commit-hook push fan-out (tools, stow, plugins)
2. `agent-sync` (agent runtime/skill definitions, agent hosts only)
3. `dotfiles-fleet-linear-key` (materialize secrets from Bao to the fleet)

These are a hand-rolled version of one capability: *bring a machine to parity*.
This repo converges them onto established tools.

## Target model

```
            ┌──────────────────────────── chezmoi ───────────────────────────┐
            │  one plane: dotfiles, tools, shell, agent defs, secrets, and the │
            │  Spark serving stack's user systemd units                        │
            │  pull-model: `chezmoi init --apply`; per-machine data; Bao secrets│
            └─────────────────────────────────────────────────────────────────┘
```

- **Pull only.** Each box self-converges on an hourly `chezmoi update` cron — no
  control-node push. This scales to VPCs that boot and provision themselves
  (cloud-init runs `chezmoi init --apply`).
- **No Ansible.** The fleet is entirely user-local (user systemd units,
  user-local tools, no root/apt), so a system/push tool had nothing to do.
  Spark's serving units (vLLM/headroom/runner) live in `dot_config/systemd/user/`,
  spark-gated via `.chezmoiignore`, with a `run_after` hook doing `daemon-reload`
  + enable. Reintroduce Ansible only if real root/apt fleet management ever
  becomes necessary.

## Cloud instance path (cattle)

1. Terraform/OpenTofu creates provider resources. For Scaleway this is the
   `provisioning/scw-instance` root module: instance, public IP, security
   group, and cloud-init user-data.
2. The operator path creates a one-use Tailscale key tagged `tag:scw-agent`,
   provisions fleet Bao AppRole material, and passes both into cloud-init.
   Cloud-init joins the tailnet with Tailscale SSH enabled, then runs
   `chezmoi init --apply --force`.
   Current implementation: `just scw-instance-*`.
3. `run_after_10` installs base tools including `bao`; `run_after_11` refreshes
   `~/.vault-token`; `run_after_12` converges the mise tool manifest; and
   `run_after_20` clones/syncs private `fhh-toolkit` using a temporary
   Bao-backed GitHub credential.
4. They self-converge on the hourly `chezmoi update` cron — no control-node or
   Ansible step; discovery is Tailscale + tags.
5. Access via Tailscale SSH + ACLs (`tag:scw-agent`) plus public SSH as the
   break-glass path during initial bootstrap.

## Migration status

| Phase | State |
|---|---|
| chezmoi installed (Spark) + repo scaffolded | ✅ done |
| chezmoi source: per-machine data, install.sh driver, agent-sync, Linear secret | ✅ done |
| Validated rendering on Spark (data + secret) without mutating any home | ✅ done |
| Ansible removed; Spark serving units migrated into chezmoi (`dot_config/systemd/user`) | ✅ done (2026-06-19) |
| **Cutover: chezmoi the live manager on spark + eigil + dicte + pi3** | ✅ done (2026-06-17), pull via @hourly cron; repo made public |
| Retire the dotfiles commit-hook fan-out | ✅ done — hook + dotfiles-fleet-sync deleted |
| **Bao reachable from the fleet** | ✅ done — ACL grant + read-only AppRole token |
| Ingvild cutover | ✅ done (2026-06-22) — `chezmoi`, Bao, mise, `fhh-toolkit`, agent config |
| Laptop pending | ⏳ user runs init |
| Scaleway instance bootstrap for agent hosts (`tag:scw-agent`, chezmoi, mise, fhh-toolkit) | ✅ validated on `scw-agent-01` (2026-06-22); OpenTofu/cloud-init path in progress |

## RESOLVED (2026-06-17): OpenBao from the fleet

Fixed. Added an additive Tailscale ACL grant `tag:tiny -> [svc:bao, tag:secrets]
: tcp:443,8200` (via the API, key from Bao `kv/projects/fos/shared/tailscale-admin`),
enabled `accept-dns` on the tinys, installed the `bao` CLI fleet-wide, and gave
each box a scoped **read-only** AppRole token (policy `fleet-kv-read`, role
`fleet-kv`) in `~/.vault-token` with creds in `~/.config/bao/approle` refreshed by
`bao-relogin`. `bao kv get` verified on all tinys. The linear-tui/scw wrappers
now read Bao at call time on every box, so `dotfiles-fleet-linear-key` was
retired. Remaining: auto-renewal timer for the periodic token. Ansible
`hashi_vault`, Ingvild cutover, and the VPC cattle path are now unblocked.
History below.

## (Historical) Known blocker: OpenBao from the fleet — it's a Tailscale ACL

Diagnosed 2026-06-17. Bao runs on eigil (`:8200`, exposed via Tailscale Serve and
reachable from Spark at `bao.olm-hops.ts.net`). The tinys **cannot reach eigil on
any port** — `dicte -> 100.87.251.112:{22,8200}` both time out, while
`spark -> eigil:8200` is open. So it is not TLS/DNS/cert/auth: the tinys are
locked-down `tagged-devices` that the tailnet **ACL** does not permit to initiate
connections to eigil (Spark can reach them; they can't reach back). MagicDNS is
also not resolving on the tinys (secondary).

**Fix (admin console only — cannot be done from the machines):** add an ACL grant
allowing the fleet tag to reach the Bao host/port, e.g.

```jsonc
// tailnet policy
{ "action": "accept", "src": ["tag:fleet"], "dst": ["<eigil/bao>:8200"] }
```

and enable MagicDNS / `--accept-dns` on the fleet nodes so `bao.olm-hops.ts.net`
resolves there. Once the tinys can reach Bao + have a scoped read-only token in
`~/.vault-token`, Bao-backed wrappers work on every box and
`dotfiles-fleet-linear-key` can be retired. Same unlock serves Ansible
`hashi_vault` and the VPC cattle path.
