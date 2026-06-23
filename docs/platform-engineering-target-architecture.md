# Platform Engineering Target Architecture

This repo should become a small-scale platform engineering system that teaches
enterprise operating patterns without pretending the current scale requires all
of the machinery.

The aim is not "more tools". The aim is clear seams:

- durable desired state lives in Git and OpenTofu stacks
- first-boot bootstrap is explicit and short-lived
- host convergence is pull-based through chezmoi and mise
- runners such as Semaphore execute the same repo-defined workflows with logs,
  approvals, and drift checks

## Current Finding

The repo is doing useful work, but its interface is still too shallow in the
Scaleway path:

- `provisioning/scw-instance` is a single-instance OpenTofu root, but the repo
  concept is broader than one instance.
- `just scw-instance-*` currently hides real cross-system work: Tailscale auth
  key minting, Bao AppRole material, OpenTofu vars, apply, and verification.
  That is acceptable while discovering the process, but it is not the long-term
  platform interface.
- Bootstrap secrets are generated outside the durable IaC model and passed into
  cloud-init. This works, but it makes `tfui` and raw `tofu plan` awkward because
  the stack has required ephemeral variables.
- Tailscale policy source currently lives in `fos`, while Scaleway host
  provisioning lives here. That splits one platform concept across repos.
- `scaleway-lab` has useful learning artifacts for remote state, but the bucket
  and state lifecycle should not remain separate from the platform repo.

The next design should concentrate these concerns into deep modules and clear
state boundaries.

## 20-Angle Review Loop

1. **Source of truth**: Git should hold durable desired state. Secrets and
   one-use bootstrap material should not be durable source.
2. **State boundary**: OpenTofu roots should map to things that are planned,
   applied, drift-checked, and destroyed together.
3. **Repo boundary**: `platform-engineering` should own shared platform
   resources. App repos should not own global network or host policy.
4. **Human interface**: Raw tools should stay raw. Use `tofu` in OpenTofu roots,
   `chezmoi` for home convergence, and `ssh` for access. Avoid small wrappers.
5. **Operator workflow**: Use recipes only when coordinating multiple systems
   with ordering and secrets, not as aliases for normal commands.
6. **Bootstrap lifecycle**: First-boot material should be short-lived,
   preauthorized, auditable, and expired by design.
7. **Secret boundary**: OpenTofu state must be treated as sensitive if user-data
   contains bootstrap material. The target design should reduce or eliminate
   secrets in state.
8. **Identity model**: Users, machines, tags, AppRoles, and Tailscale ACLs need
   one vocabulary and one catalog.
9. **Network model**: Tailscale tags, grants, SSH rules, and services are
   platform resources, not side notes in an app repo.
10. **Host convergence**: Chezmoi owns user config; mise owns tools; root is
    bootstrap and repair only.
11. **Ongoing convergence**: Hourly `chezmoi-sync` is the fleet reconciliation
    loop. It needs logging, failure visibility, and a manual repair path.
12. **Verification**: Every stack needs acceptance checks that prove the real
    outcome, not only a successful apply.
13. **Drift detection**: Scheduled plan-only runs should report drift without
    changing anything.
14. **Teardown**: Destroy should remove cloud resources, tailnet device records,
    and generated local bootstrap files.
15. **Disaster recovery**: Remote state, state locking, state versioning, and
    documented restore are part of the platform, not optional polish.
16. **Cost control**: Tags, TTL conventions, inventory, and periodic empty-state
    checks teach cloud cost hygiene early.
17. **Observability**: Cloud-init logs, convergence logs, runner logs, and
    verification output should make a failed bootstrap diagnosable without SSH
    archaeology.
18. **Inspection ergonomics**: `tfui` and `tofu plan` should work from the stack
    directory with stable variable files for durable config. Ephemeral bootstrap
    should not be required just to inspect long-lived resources.
19. **Runner model**: Semaphore should run repo-defined plan/apply/verify jobs.
    It should not become the place where platform logic lives.
20. **Learning model**: Docs should explain why enterprise patterns exist:
    state, drift, approval, audit, least privilege, runbooks, and recovery.
21. **Portability**: Cloud-init and chezmoi are mostly provider-neutral; cloud
    resource stacks are provider-specific adapters.
22. **Module depth**: A module earns its place only if deleting it would spread
    complexity across callers.
23. **Policy as code**: Tailscale ACL tests and future policy checks belong in
    the same review path as infrastructure changes.
24. **Scale rehearsal**: Even with one VM, use the habits that scale: catalogs,
    environments, remote state, drift checks, and explicit ownership.
25. **Disposable development environments**: Devcontainers and DevPod are
    execution adapters for the same baseline, not a second dotfiles system.
    `k3d` is the local rehearsal target for k3s/Kubernetes changes before they
    touch the tinys cluster.

## Target Repo Shape

Recommended structure:

```text
platform-engineering/
  CONTEXT.md
  docs/
    adr/
    runbooks/
    learning/
    platform-engineering-target-architecture.md
  catalogs/
    hosts.yaml
    capabilities.yaml
    environments.yaml
  environments/
    devcontainer/
    k3d/
  home/
    ... chezmoi source ...
  provisioning/
    modules/
      scaleway-instance/
      cloud-init-platform-host/
    stacks/
      scaleway-foundation/
      scaleway-compute/
      tailnet/
  operations/
    semaphore/
      task-templates/
      schedules/
  tests/
    cloud-init/
    policy/
    tofu/
```

### Why this shape

- `home/` stays as the chezmoi source. It is the host baseline plane.
- `provisioning/modules/` holds reusable implementation. Callers should not need
  to understand all cloud-init details to create a platform host.
- `provisioning/stacks/` holds state boundaries. These are the places where raw
  `tofu plan`, `tfui`, and Semaphore tasks run.
- `catalogs/` becomes the human-readable inventory: hosts, capabilities, tags,
  and environments. This is where you learn how enterprises avoid mystery
  infrastructure.
- `operations/semaphore/` records how automation runs the repo. Semaphore is a
  runner, not a source of truth.
- `environments/` holds disposable development targets that consume the same
  baseline as real hosts. Devcontainers/DevPod give people and agents a
  repeatable workstation; `k3d` gives k3s/Kubernetes changes a safe rehearsal
  cluster before the tinys.
- `docs/adr/` records decisions so future agents do not rediscover and reargue
  the same tradeoffs.

## Proposed State Boundaries

### `provisioning/stacks/scaleway-foundation`

Owns long-lived Scaleway foundation:

- Object Storage bucket for OpenTofu state
- state locking configuration
- project-level tags and naming conventions where supported
- optional IAM/API credentials once represented safely

This stack is applied rarely and destroyed deliberately. It teaches the
enterprise idea that state storage is infrastructure too.

### `provisioning/stacks/scaleway-compute`

Owns desired Scaleway hosts as a small fleet, not one root per host:

```hcl
instances = {
  scw-instance-01 = {
    type = "DEV1-S"
    zone = "fr-par-1"
    role = "scw-instance"
    capabilities = ["fhh-toolkit"]
  }
}
```

OpenTofu should be able to plan the durable resources without minting new
one-use secrets on every inspection.

### `provisioning/stacks/tailnet`

Eventually owns Tailscale policy, grants, SSH rules, tests, and service
definitions. This probably migrates from `fos/platform/tailscale` once the repo
is ready to be the platform source of truth.

Until then, keep `fos` as the live policy source but document it as an external
dependency of this repo.

## Bootstrap Design

The current bootstrap path passes these into cloud-init:

- Tailscale one-use auth key
- Bao AppRole role ID and secret ID
- operator SSH key

That is acceptable for discovery, but the target is stricter:

1. Durable OpenTofu plan should model cloud resources without needing fresh
   bootstrap secrets.
2. Bootstrap material should be minted only at apply time or by the runner.
3. Bootstrap material should have short TTLs and narrow scope.
4. State containing bootstrap material must be remote, encrypted, access
   controlled, and treated as sensitive.
5. The longer-term target is instance identity or workload identity so the host
   can authenticate to the secret system without storing one-use credentials in
   OpenTofu state.

This is the main architectural problem to solve before calling the Scaleway path
enterprise-grade.

## Semaphore Role

Semaphore should provide:

- plan task
- apply task with approval
- destroy task with approval
- scheduled drift check
- scheduled empty-resource/cost check
- verification task
- logs and audit trail

Semaphore should not contain hidden platform logic. It should run commands from
this repo against named OpenTofu stacks.

## Command Philosophy

Do not add small hacker wrappers.

Use direct tools where they are the interface:

```sh
cd provisioning/stacks/scaleway-compute
tofu plan
tfui -binary tofu -dir .
```

Use recipes only where the interface is deeper than the underlying command:

- minting bootstrap material
- preparing an apply workspace
- applying a stack with the right secrets
- verifying a host across Tailscale, Bao, chezmoi, and mise

If a recipe is just an alias for a command, delete it.

## Migration Plan

### Phase 0: Stabilize the Current Slice

- Keep `provisioning/scw-instance` working as the known-good slice.
- Add a clear README note that raw `tofu`/`tfui` belongs in the OpenTofu root.
- Keep generated bootstrap files ignored and remove them after teardown.
- Keep using normal OpenSSH over the tailnet for verification.

### Phase 1: Record the Platform Domain

- Add `CONTEXT.md` with stable terms:
  - platform baseline
  - host capability
  - resource stack
  - bootstrap material
  - convergence loop
  - runner
  - tailnet policy
- Add ADRs for:
  - repo root is not an OpenTofu root
  - OpenSSH over tailnet is preferred for Scaleway access
  - Semaphore is a runner, not source of truth
  - no small wrappers for raw tool commands

### Phase 2: Introduce Remote State Properly

- Promote the useful `scaleway-lab` learning into
  `provisioning/stacks/scaleway-foundation`.
- Create the state bucket and locking path as a deliberate foundation stack.
- Move Scaleway compute state off local disk before Semaphore runs it.
- Document restore and destroy of state infrastructure.

### Phase 3: Move From Single Instance to Compute Fleet

- Replace `provisioning/scw-instance` with
  `provisioning/stacks/scaleway-compute`.
- Model `instances` as a map.
- Extract reusable implementation into modules only when two callers need it.
- Keep cloud-init rendering testable.
- Make `tfui` useful by separating durable variables from ephemeral bootstrap
  material.

### Phase 4: Bring Tailnet Policy Under Platform Ownership

- Decide whether Tailscale policy moves from `fos` into this repo.
- If yes, migrate policy, tests, and apply runbook together.
- Keep `fos` focused on app/product concerns.

### Phase 5: Add Runner Operations

- Add Semaphore task templates for plan/apply/destroy/verify/drift.
- Ensure all tasks run from stack directories using the same state backend.
- Require approval for apply and destroy.
- Schedule drift and empty-resource checks.

### Phase 6: Improve Bootstrap Identity

- Short term: keep one-use Tailscale keys and Bao AppRole secret IDs, but run
  them only in ephemeral runner/operator workspaces.
- Medium term: use response-wrapped or TTL-bound bootstrap material.
- Long term: use provider/instance identity so a host proves who it is instead
  of receiving long-lived credentials through user-data.

## Deepening Opportunities

1. **Resource stack module**
   - Files: `provisioning/scw-instance/*`, `scaleway-lab/main.tf`
   - Problem: one instance and one lab bucket are separate learning slices.
   - Solution: introduce foundation and compute stacks with clear state
     boundaries.
   - Benefit: better locality for plan/apply/drift and better leverage from
     OpenTofu.

2. **Bootstrap material module**
   - Files: `Justfile`, `platform-host.cloud-init.yaml.tftpl`
   - Problem: ephemeral Tailscale/Bao material is mixed into planning.
   - Solution: make bootstrap material an explicit concept with TTL, scope, and
     lifecycle.
   - Benefit: safer state, cleaner inspection, easier Semaphore execution.

3. **Host catalog module**
   - Files: `home/.chezmoi.toml.tmpl`, Tailscale policy refs, OpenTofu vars
   - Problem: host role/capability knowledge is duplicated across templates,
     policy, and docs.
   - Solution: introduce a catalog that describes hosts and capabilities.
   - Benefit: one place to teach and change the platform vocabulary.

4. **Runner module**
   - Files: future `operations/semaphore/*`
   - Problem: local shell flow does not teach approval, audit, drift, or shared
     operations.
   - Solution: encode Semaphore tasks as runner definitions that call repo
     stacks.
   - Benefit: enterprise operating habits without moving logic into the UI.

5. **Verification module**
   - Files: `Justfile`, docs, future `tests/`
   - Problem: verification is a command string rather than a testable interface.
   - Solution: define acceptance checks per stack and host capability.
   - Benefit: better failure locality and reusable post-apply confidence.

## Immediate Next Decision

Do not start by writing code.

Choose the next state boundary:

1. `scaleway-foundation` first, if the next lesson is remote state and
   Semaphore readiness.
2. `scaleway-compute` first, if the next lesson is multi-instance fleet design.
3. `tailnet` first, if the next lesson is policy-as-code and platform ownership.

Recommended next move: **`scaleway-foundation` first**. It unlocks remote state,
tfui inspection, Semaphore, and drift checks without changing host bootstrap
again.
