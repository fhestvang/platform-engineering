# Scaleway Agent Bootstrap

This is the repeatable path for cattle-style Scaleway agent VMs.

## What we learned from `scw-agent-01`

- Browser-based `tailscale up` is a bad bootstrap primitive over SSH: it looks
  idle while waiting for an approval URL and is easy to interrupt.
- Scaleway agents should join the tailnet as `tag:scw-agent`, not as untagged
  user devices. The tag has narrow grants: Bao, Spark LiteLLM `:8444`, and SSH
  from owner/admin/dev-laptop/Spark.
- Repair runs against an already-joined VM must drop the old user-owned
  Tailscale identity before the tagged auth key can take effect. The bootstrap
  script does this with `tailscale logout` before `tailscale up`, and therefore
  assumes public SSH remains available during repair.
- `chezmoi` can install `bao`, but agent sync needs a live Bao token before it
  clones private `fhh-toolkit`. `run_after_11-bao-relogin` now refreshes
  `~/.vault-token` from pre-provisioned AppRole material before agent sync.
- Run multi-step remote convergence from a script file on the VM, not from a
  multiline `sudo -iu ... bash -lc` string. The latter can collapse newlines
  under login-shell handoff and break shell syntax.
- `fhh-toolkit` is private. `run_after_20-agent-sync` uses a temporary
  `GIT_ASKPASS` helper that reads the GitHub token from Bao at call time; the
  token is not written to disk.
- `mise` tools are shims. The shims path must be in non-interactive shell PATHs,
  so `.zshenv` and `.bashrc` now add `~/.local/share/mise/shims`.
- Ubuntu packages expose `fd` and `bat` as `fdfind` and `batcat`; `dotfiles`
  now creates compatibility aliases when apt already installed the packages.
- Current `mise` direct release discovery can fail; `dotfiles` now falls back to
  the official `https://mise.run` installer.

## One-command Operator Path

Prerequisites on the operator machine:

- The live Tailscale ACL has `tag:scw-agent` from `fos/platform/tailscale/policy.hujson`.
- `bao`, `curl`, `jq`, and `ssh` are installed.
- Bao has:
  - `kv/projects/fos/shared/tailscale-admin` with `TAILSCALE_API_KEY`
  - AppRole `fleet-kv` with policy `fleet-kv-read`
- The new Scaleway VM accepts public SSH as `root`.

Run from `fleet-provisioning`:

```sh
bash scripts/bootstrap-scaleway-agent.sh <public-ip> scw-agent-02
```

The script creates a one-use, one-hour auth key tagged `tag:scw-agent`, creates
fresh `fleet-kv` AppRole material, provisions the `fhestvang` user, joins
Tailscale with SSH enabled, runs `chezmoi`, and verifies the agent toolchain.

## Verification

On the VM:

```sh
chezmoi data | grep -E 'hostname|role|isAgentHost'
for c in mise node nvim lazygit codex claude pi; do command -v "$c"; done
bao kv get -field=GITHUB_TOKEN kv/projects/fos/shared/github-cli >/dev/null
test -d ~/github/fhh-toolkit/.git
crontab -l | grep chezmoi-sync
```

From Spark or an owner/admin tailnet device:

```sh
tailscale ping --c 1 scw-agent-02
tailscale ssh fhestvang@scw-agent-02 hostname
tailscale ssh root@scw-agent-02 hostname
```

Expected:

- hostname starts with `scw-`
- chezmoi role is `scw-agent`
- `isAgentHost` is `true`
- `codex`, `claude`, and `pi` resolve through mise shims
- `fhh-toolkit` exists and agent config has synced
- hourly `chezmoi-sync` is installed

If regular OpenSSH over MagicDNS fails with `Host key verification failed`
after a rebuild or retag, clear the stale local key and retry:

```sh
ssh-keygen -R scw-agent-02.olm-hops.ts.net
ssh fhestvang@scw-agent-02.olm-hops.ts.net hostname
```

## Manual Fallback

Only use this when debugging the script.

1. Create a one-use preauthorized Tailscale key tagged `tag:scw-agent`.
2. Create fresh `fleet-kv` AppRole material:

   ```sh
   BAO_ADDR=https://bao.olm-hops.ts.net bao read -field=role_id auth/approle/role/fleet-kv/role-id
   BAO_ADDR=https://bao.olm-hops.ts.net bao write -f -field=secret_id auth/approle/role/fleet-kv/secret-id
   ```

3. On the VM, join Tailscale:

   ```sh
   sudo tailscale up --reset --auth-key="$TS_AUTHKEY" --ssh --accept-dns=true --hostname=scw-agent-02
   ```

4. Put the AppRole material in `~/.config/bao/approle` for `fhestvang`.
5. Run:

   ```sh
   sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
   ~/.local/bin/chezmoi --force init --apply https://github.com/fhestvang/fleet-provisioning.git
   ```

If `chezmoi` stops because a managed file changed during a retry, use:

```sh
~/.local/bin/chezmoi --force update
```
