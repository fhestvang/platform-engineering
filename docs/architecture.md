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
            ┌──────────────────────────── Ansible ───────────────────────────┐
            │  system plane (packages/sudo, services, users)  +  orchestration │
            │  static inventory (pets) + Scaleway dynamic inventory (VPCs)      │
            └───────────────────────────────┬─────────────────────────────────┘
                                             │ runs, per host
                                             ▼
            ┌──────────────────────────── chezmoi ───────────────────────────┐
            │  user-env plane: dotfiles, tools, shell, agent defs, secrets     │
            │  pull-model: `chezmoi init --apply`; per-machine data; Bao secrets│
            └─────────────────────────────────────────────────────────────────┘
```

- **Pull** (chezmoi / `ansible-pull`) self-converges a box — scales to VPCs that
  boot and provision themselves (cloud-init runs the bootstrap).
- **Push** (`ansible-playbook site.yml`) converges the known fleet from a control
  node.

## VPC path (cattle), when instances exist

1. Terraform/OpenTofu creates instances tagged `fleet`.
2. cloud-init: install Tailscale with an ephemeral, tagged, pre-auth key (joins
   the tailnet, no manual key copy), then `chezmoi init --apply`.
3. `inventory/scaleway.yml` auto-discovers them by tag for ongoing Ansible runs.
4. Access via Tailscale SSH + ACLs (no per-host authorized_keys / known_hosts).

## Migration status

| Phase | State |
|---|---|
| chezmoi installed (Spark) + repo scaffolded | ✅ done |
| chezmoi source: per-machine data, install.sh driver, agent-sync, Linear secret | ✅ done |
| Validated rendering on Spark (data + secret) without mutating any home | ✅ done |
| Ansible scaffold: inventory (static + Scaleway stub), site.yml, chezmoi role | ✅ done |
| **Apply on a live fleet box** (real cutover) | ⏳ deliberate, one box at a time |
| Retire the dotfiles commit-hook fan-out after cutover | ⏳ pending |
| **Bao reachable from the fleet** (CA trust + AppRole) | ❌ blocker — gates fleet secret rendering + Ansible vault + VPCs |
| System Ansible role (sudo packages/services) | ⏳ stub |

## Known blocker: OpenBao from the fleet

Bao answers from Spark but not the tinys (TLS/CA or the port-less proxy). Until
fixed: `baoReachable=false` on the fleet, chezmoi skips the secret file there,
and `dotfiles-fleet-linear-key` remains the fleet secret path. Solving it (CA
trust + per-machine AppRole) is the shared prerequisite for fleet secret
rendering, Ansible `hashi_vault`, and the VPC cattle path.
