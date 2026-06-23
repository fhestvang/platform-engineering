# Scaleway Instance Bootstrap

This is the repeatable path for cattle-style Scaleway instances that join the
platform baseline.

## What we learned from the first Scaleway instance

- Browser-based `tailscale up` is a bad bootstrap primitive over SSH: it looks
  idle while waiting for an approval URL and is easy to interrupt.
- Scaleway instances should join the tailnet as `tag:scw-instance`, not as
  untagged user devices. The tag has narrow grants: Bao, Spark LiteLLM `:8444`,
  and SSH from owner/admin/dev-laptop/Spark.
- Repair runs against an already-joined VM must drop the old user-owned
  Tailscale identity before the tagged auth key can take effect. Cloud-init
  does this with `tailscale logout` before `tailscale up`.
- `chezmoi` can install `bao`, but toolkit sync needs a live Bao token before
  it clones private `fhh-toolkit`. `run_after_11-bao-relogin` now refreshes
  `~/.vault-token` from pre-provisioned AppRole material before toolkit sync.
- Run multi-step remote convergence from a script file on the VM, not from a
  multiline `sudo -iu ... bash -lc` string. The latter can collapse newlines
  under login-shell handoff and break shell syntax.
- `fhh-toolkit` is private. `run_after_20-toolkit-sync` uses a temporary
  `GIT_ASKPASS` helper that reads the GitHub token from Bao at call time; the
  token is not written to disk.
- `mise` tools are shims. The shims path must be in non-interactive shell PATHs,
  so `.zshenv` and `.bashrc` now add `~/.local/share/mise/shims`.
- Ubuntu packages expose `fd` and `bat` as `fdfind` and `batcat`; `dotfiles`
  now creates compatibility aliases when apt already installed the packages.
- Current `mise` direct release discovery can fail; `dotfiles` now falls back to
  the official `https://mise.run` installer.

## Operator Path

Prerequisites on the operator machine:

- The live Tailscale ACL has `tag:scw-instance` from `fos/platform/tailscale/policy.hujson`.
- `bao`, `curl`, `jq`, `just`, and `tofu` are installed.
- Bao has:
  - `kv/projects/fos/shared/tailscale-admin` with `TAILSCALE_API_KEY`
  - AppRole `fleet-kv` with policy `fleet-kv-read`
- Bao has Scaleway credentials at `kv/projects/scaleway/cli`.

Run from `platform-engineering`:

```sh
just scw-instance-init
just scw-instance-plan scw-instance-02
just scw-instance-apply scw-instance-02
just scw-instance-verify scw-instance-02
```

The `prepare` step creates a one-use, one-hour auth key tagged
`tag:scw-instance` and fresh `fleet-kv` AppRole material. OpenTofu creates the
Scaleway instance, public IP, security group, and cloud-init payload.
Cloud-init provisions the `fhestvang` user, joins Tailscale with SSH enabled,
runs `chezmoi`, and the verify step checks the attached toolkit capability.

## Access Model

Use `root` only for first bootstrap and break-glass system repair. Root is not a
working environment and intentionally has no `mise`, toolkit commands, dotfiles,
Bao wrappers, or `fhh-toolkit`.

After first boot, use the `fhestvang` user:

```sh
ssh fhestvang@<public-ip>
ssh scw-instance-02
```

Use root only when repairing the machine itself:

```sh
ssh root@<public-ip>
```

## Verification

On the VM:

```sh
chezmoi data | grep -E 'hostname|role|hasFhhToolkit'
for c in mise node nvim lazygit starship fzf zoxide fd rg bat eza atuin direnv yazi tmux sesh btop gh gh-dash kubectl k9s k3d dagger skaffold glow lazydocker codex claude pi; do command -v "$c"; done
bao kv get -field=GITHUB_TOKEN kv/projects/fos/shared/github-cli >/dev/null
test -d ~/github/fhh-toolkit/.git
crontab -l | grep chezmoi-sync
```

From Spark or an owner/admin tailnet device:

```sh
tailscale ping --c 1 scw-instance-02
ssh scw-instance-02 hostname
```

Expected:

- hostname starts with `scw-instance-`
- chezmoi role is `scw-instance`
- `hasFhhToolkit` is `true`
- terminal/workstation tools, Kubernetes tools, Dagger, Skaffold, and `sesh`
  resolve through mise shims
- `codex`, `claude`, and `pi` resolve through mise shims when fhh-toolkit is attached
- `fhh-toolkit` exists and toolkit config has synced
- hourly `chezmoi-sync` is installed

If regular OpenSSH over MagicDNS fails with `Host key verification failed`
after a rebuild or retag, clear the stale local key and retry:

```sh
ssh-keygen -R scw-instance-02.olm-hops.ts.net
ssh fhestvang@scw-instance-02.olm-hops.ts.net hostname
```

## Manual Fallback

Only use this when debugging cloud-init or OpenTofu.

1. Create a one-use preauthorized Tailscale key tagged `tag:scw-instance`.
2. Create fresh `fleet-kv` AppRole material:

   ```sh
   BAO_ADDR=https://bao.olm-hops.ts.net bao read -field=role_id auth/approle/role/fleet-kv/role-id
   BAO_ADDR=https://bao.olm-hops.ts.net bao write -f -field=secret_id auth/approle/role/fleet-kv/secret-id
   ```

3. On the VM, join Tailscale:

   ```sh
   sudo tailscale up --reset --auth-key="$TS_AUTHKEY" --ssh --accept-dns=true --hostname=scw-instance-02
   ```

4. Put the AppRole material in `~/.config/bao/approle` for `fhestvang`.
5. Run:

   ```sh
   sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
   ~/.local/bin/chezmoi --force init --apply https://github.com/fhestvang/platform-engineering.git
   ```

If `chezmoi` stops because a managed file changed during a retry, use:

```sh
~/.local/bin/chezmoi --force update
```
