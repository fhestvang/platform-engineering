# Scaleway Instance Provisioning

This is the clean path for cattle-style Scaleway instances that join the
platform baseline.

## Concepts

- OpenTofu owns cloud resources: Instance, public IP, security group, and the
  first-boot user-data payload.
- Cloud-init runs inside the VM on first boot. It creates `fhestvang`, installs
  Docker and Tailscale, joins the tailnet as `tag:scw-instance`, writes Bao
  AppRole material, and starts chezmoi convergence.
- Chezmoi owns the user environment after first boot: dotfiles, mise tools,
  Bao wrappers, `fhh-toolkit`, and hourly convergence.
- `just` is only the command runner. It gives this module stable commands and
  keeps the operator workflow out of ad hoc shell history.

## Bootstrap Secrets

The generated `.generated/<hostname>.auto.tfvars.json` and local OpenTofu state
contain bootstrap secrets. They are ignored by git.

The Tailscale auth key is one-use and expires after one hour. Apply the plan
soon after running `just scw-instance-plan`; if the key expires, rerun the plan.

The server resource ignores `user_data` drift after creation. Cloud-init is
create-time input, and the generated bootstrap credentials are intentionally
ephemeral. Use chezmoi/mise for ongoing convergence, or replace the instance
when first-boot behavior itself must be proven again.

## Usage

```sh
cd ~/github/platform-engineering
just scw-instance-init
just scw-instance-plan scw-instance-02
just scw-instance-apply scw-instance-02
just scw-instance-verify scw-instance-02
```

For a single create command:

```sh
just scw-instance-create scw-instance-02
```

## Access Model

Use `root` only as break-glass system access. The working environment is the
`fhestvang` user:

```sh
ssh scw-instance-02
```

Root intentionally has no dotfiles, mise shims, Bao wrappers, toolkit commands,
or `fhh-toolkit`.

## Why This Replaced The SSH Bootstrap Script

The old SSH bootstrap script mixed credential minting, remote root SSH, OS
setup, tailnet join, chezmoi convergence, and verification. That was useful
while discovering the process, but it was a shallow interface: the caller still
had to understand all of the implementation.

This module has clearer responsibilities:

- OpenTofu: desired cloud resources.
- cloud-init: first boot.
- chezmoi: user convergence.
- `just`: operator command names.
