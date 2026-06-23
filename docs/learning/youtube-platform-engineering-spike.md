# Learning Spike: Platform Engineering From the YouTube Audit

Purpose: turn the recent video audit into a practical learning note for
Frederik's current `platform-engineering` repo, especially the Scaleway VM path.
This is a docs-only spike, not an implementation plan.

Sources reviewed:

- `tmp/youtube-learning/rqpiVgWZBOg.clean.txt`:
  "Supercharge your development workflow with these CLI tools"
- `tmp/youtube-learning/MHPRnM38Dyc.clean.txt`:
  "The Forever Timeless Terminal Setup"
- Repo files: `README.md`, `docs/scw-instance-bootstrap.md`,
  `docs/platform-engineering-target-architecture.md`,
  `home/run_onchange_after_12-mise-install.sh.tmpl`,
  `home/dot_config/mise/config.toml.tmpl`,
  `home/dot_config/tmux/tmux.conf`

## Governing Idea

The audit reinforces the repo's current split:

- Chezmoi owns the home environment: dotfiles, shell config, tmux, wrappers,
  user units, per-machine facts, and convergence scripts.
- Mise owns the tools and runtimes through one committed manifest.
- New hosts should converge from Git and Bao, not from manual SSH edits.

That is the platform lesson: desired state is declarative enough to repeat, but
small enough to understand.

## Tool Notes

| Topic | What to Learn | Current Repo Relevance |
|---|---|---|
| Chezmoi `run_onchange` + mise hash | `run_onchange` reruns when the rendered script changes. The repo embeds `{{ includeTemplate "dot_config/mise/config.toml.tmpl" . \| sha256sum }}` in `home/run_onchange_after_12-mise-install.sh.tmpl`, so editing the rendered mise manifest triggers `mise install`. | Prevents stale tools after a manifest change, including host-specific changes from `hasFhhToolkit`. |
| Mise as tool manifest | Mise is the fleet tool contract, not just a version manager. Foundation tools are pinned; utility and fast-moving CLIs float. | `home/dot_config/mise/config.toml.tmpl` declares foundation runtimes, terminal/workstation CLIs such as `starship`, `fzf`, `zoxide`, `ripgrep`, `bat`, `eza`, `atuin`, `tmux`, `sesh`, `btop`, `gh`, and `gh-dash`, platform tools such as `kubectl`, `k9s`, `k3d`, `dagger`, `skaffold`, and toolkit-gated coding CLIs. |
| k3d / k3s | `k3s` is the lightweight Kubernetes runtime. `k3d` runs k3s clusters in Docker containers. | The tinys cluster is the real k3s environment; k3d is the disposable rehearsal target before touching it. |
| Dagger | Portable, containerized workflow steps that can run locally or in automation. Good for build/test/service checks that should not depend on one host. | Installed by mise as a candidate tool. No Dagger workflow is source of truth yet. |
| Skaffold | Kubernetes dev loop: build, tag, deploy, watch, and tail logs against a selected cluster. | Installed by mise. First useful target should be k3d, not the live tinys cluster. |
| DevPod / devcontainers | A project can define its runtime while the operator keeps familiar dotfiles and shell behavior. DevPod starts devcontainer environments outside VS Code. | Target architecture names `environments/devcontainer/`, but no implementation exists yet. `devpod` is not currently in the mise manifest. |
| Sesh | Tmux session navigation becomes part of the working interface. | Mise installs `github:joshmedeski/sesh`; tmux binds prefix `S`, `L`, and `9` to picker/last/connect flows. |

## Audit Coverage

This is the explicit pass over both videos so the important items are not hidden
inside a prose summary.

| Source | Tool / Concept | Decision |
|---|---|---|
| Supercharge workflow | Starship | In mise. Shell prompt config already exists. |
| Supercharge workflow | Bluefin / immutable OS | Learn the model; do not add to this repo now. It is an operating-system choice, not a VM baseline tool. |
| Supercharge workflow | Distrobox / Podman GUI containers | Defer. Useful on a Linux desktop for GUI/hardware isolation, but not part of Scaleway VM bootstrap. |
| Supercharge workflow | DevPod / devcontainers | Architecture target, not implemented yet. Add `devpod` only when `environments/devcontainer/` exists. |
| Supercharge workflow | Chezmoi | Already the convergence engine. |
| Supercharge workflow | Mise | Already the tool contract; now widened to include terminal/workstation tools too. |
| Supercharge workflow | Bat / Eza / FZF / Zoxide / Ripgrep / fd | In mise because shell config and aliases use them. |
| Supercharge workflow | k3d / k9s / kubectl | In mise. k3d is the disposable k3s rehearsal target. |
| Supercharge workflow | Dagger | In mise as the first portable workflow/service orchestration spike. |
| Supercharge workflow | Docker Compose | Keep as project-local service composition; do not put Docker itself in mise. |
| Supercharge workflow | `fd` + `entr` live-reload loop | Represented by `fd` and `watchexec` in mise. Do not add a second watcher until a real loop needs it. |
| Supercharge workflow | Skaffold | In mise as the first Kubernetes dev-loop candidate. |
| Supercharge workflow | Tilt | Defer. More UI and config; evaluate only after a Skaffold/k3d slice. |
| Supercharge workflow | ASDF / UBI / GitHub release backends | Represented by mise backends; use `github:`/aqua tools when registry names are missing. |
| Supercharge workflow | Team communication / ADRs | Already reflected in target architecture docs; keep decisions in docs, not chat memory. |
| Terminal setup | Ghostty / Kitty / WezTerm / fonts | Client-side terminal choices. Keep outside Scaleway VM baseline. |
| Terminal setup | Fastfetch / Chafa | Defer. Nice inspection/visual tool, not required for the platform workflow. |
| Terminal setup | Zsh profile split / vi mode | Already represented in shell config. Do not add ZVM unless the keybinding tradeoff is accepted. |
| Terminal setup | Starship | In mise and configured. |
| Terminal setup | Tmux / TPM plugins | Tmux is in mise; TPM plugins remain tmux-managed. |
| Terminal setup | Sesh | In mise because tmux config calls it directly. |
| Terminal setup | Atuin | In mise; Bao-backed login hook already exists. |
| Terminal setup | GH CLI / gh-dash | In mise because Git and gh-dash config reference them. |
| Terminal setup | btop | In mise because btop config is checked in. |
| Terminal setup | tree / lstr | Covered by `eza --tree` and existing aliases rather than a new tool. |
| Terminal setup | Insforge / MCP sponsor segment | Do not add. Interesting agent-backend pattern, but not part of this platform baseline. |

## Practical Example: New Scaleway VM

Goal: create a cattle-style host such as `scw-instance-02`.

```sh
cd ~/github/platform-engineering
just scw-instance-init
just scw-instance-plan scw-instance-02
just scw-instance-apply scw-instance-02
just scw-instance-verify scw-instance-02
```

What happens:

- `just` sequences the operator flow.
- Bao supplies Scaleway credentials, the Tailscale admin token, and fleet
  AppRole material at call time.
- Tailscale gives the VM a one-use `tag:scw-instance` identity.
- OpenTofu creates the Scaleway instance, IP, security group, and cloud-init
  payload.
- Cloud-init creates `fhestvang`, joins the tailnet, writes bootstrap AppRole
  material, and starts chezmoi.
- Chezmoi renders the role-aware home baseline.
- `run_after_10` installs base tools; `run_after_11` refreshes the Bao token.
- `run_onchange_after_12` runs `mise install` because the mise manifest hash is
  embedded in the rendered script.
- Mise installs the declared tools, including terminal/workstation CLIs, k3d,
  Dagger, Skaffold, and `sesh`.
- Toolkit-capable hosts sync `fhh-toolkit`.
- The hourly `chezmoi-sync` cron keeps the host converged.

How each audit tool fits this story:

- Chezmoi: host convergence from Git.
- Mise: repeatable user tool surface, including the terminal tools from the
  audit and the platform dev-loop tools.
- k3d: local k3s rehearsal cluster.
- k3s: real lightweight Kubernetes runtime on the tinys.
- Dagger: candidate for portable platform checks.
- Skaffold: candidate for Kubernetes app loops against k3d.
- DevPod/devcontainers: future disposable project workspaces that consume the
  same baseline rather than forking it.
- Sesh: fast return to the right tmux context while operating the platform.

Verification already exists:

```sh
just scw-instance-verify scw-instance-02
```

It checks tailnet reachability, SSH as `fhestvang`, chezmoi role data, the
important mise shims, Bao access to the GitHub token, `fhh-toolkit`, and the
hourly convergence cron.

## Hands-On Spike

1. Read `home/run_onchange_after_12-mise-install.sh.tmpl` and explain why the
   hash belongs in the script body.
2. Compare `mise list` on a real host with
   `home/dot_config/mise/config.toml.tmpl`.
3. Create and delete a disposable k3d cluster; confirm `kubectl` and `k9s` use
   the intended context.
4. Sketch, but do not commit, one Skaffold loop against k3d.
5. Sketch, but do not commit, one Dagger check that could later run locally or
   in CI.
6. Try DevPod with a throwaway devcontainer and note what dotfiles hook is
   needed for a normal shell experience.
7. Use tmux + `sesh` during the spike and decide whether the current bindings
   are sufficient.

## Decisions to Revisit

- Should `devpod` join the mise manifest before a real devcontainer exists?
- What is the first workload that deserves a k3d rehearsal path?
- Should Dagger wait for Semaphore/drift workflows, or own a small local check
  sooner?
- Should Skaffold examples live here or in app repos?
- What observable output should `chezmoi-sync` produce when `mise install`
  fails remotely?
