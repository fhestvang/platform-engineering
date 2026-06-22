# Scaleway Instance Provisioning

This is the clean path for cattle-style Scaleway instances that become
platform agent hosts.

## Concepts

- OpenTofu owns cloud resources: Instance, public IP, security group, and the
  first-boot user-data payload.
- Cloud-init runs inside the VM on first boot. It creates `fhestvang`, installs
  Tailscale, joins the tailnet as `tag:scw-agent`, writes Bao AppRole material,
  and starts chezmoi convergence.
- Chezmoi owns the user environment after first boot: dotfiles, mise tools,
  Bao wrappers, `fhh-toolkit`, and hourly convergence.
- `just` is only the command runner. It gives this module stable commands and
  keeps the operator workflow out of ad hoc shell history.

## Bootstrap Secrets

The generated `.generated/<hostname>.auto.tfvars.json` and local OpenTofu state
contain bootstrap secrets. They are ignored by git.

The Tailscale auth key is one-use and expires after one hour. Apply the plan
soon after running `just scw-instance-plan`; if the key expires, rerun the plan.

## Usage

```sh
cd ~/github/fleet-provisioning
just scw-instance-init
just scw-instance-plan scw-agent-02
just scw-instance-apply scw-agent-02
just scw-instance-verify scw-agent-02
```

For a single create command:

```sh
just scw-instance-create scw-agent-02
```

## Access Model

Use `root` only as break-glass system access. The working environment is the
`fhestvang` user:

```sh
ssh scw-agent-02
tailscale ssh fhestvang@scw-agent-02
```

Root intentionally has no dotfiles, mise shims, Bao wrappers, agent commands,
or `fhh-toolkit`.

## Why This Replaced The SSH Bootstrap Script

The old `scripts/bootstrap-scaleway-agent.sh` mixed credential minting,
remote root SSH, OS setup, tailnet join, chezmoi convergence, and verification.
That was useful while discovering the process, but it was a shallow interface:
the caller still had to understand all of the implementation.

This module has clearer responsibilities:

- OpenTofu: desired cloud resources.
- cloud-init: first boot.
- chezmoi: user convergence.
- `just`: operator command names.
