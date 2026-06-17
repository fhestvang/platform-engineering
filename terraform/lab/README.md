# lab: disposable Scaleway VM, provisioned from current fleet definitions

A hands-on lab that creates one cheap, disposable Scaleway instance via OpenTofu,
joins it to the tailnet as `tag:scw-vm`, and converges it with the dotfiles
installer, then you SSH in and work from it. Local state (isolated from the
`scaleway-lab` project's S3 state).

## Run

```sh
cd terraform/lab
source env.sh                         # scw creds from OpenBao

# inputs passed at apply time, never committed:
export TF_VAR_ssh_pubkey="$(cat ~/.ssh/spark_to_tinys_ed25519.pub)"
export TF_VAR_tailscale_authkey="tskey-auth-..."   # ephemeral, tag:scw-vm

tofu init
tofu plan
tofu apply

# wait ~1-2 min for cloud-init, then:
tofu output ssh_tailnet
ssh fhestvang@scw-vm-lab.olm-hops.ts.net

# when done:
tofu destroy
```

## What provisions it

`cloud-init.yaml.tftpl`: installs Tailscale and joins as `tag:scw-vm` (so the ACL
grants it `svc:bao` read and lets your machines SSH in), then clones the dotfiles
repo and runs `install.sh --install-packages --auto-zsh`. The ephemeral tailnet
node auto-removes on `destroy`.

## Cost

STARDUST1-S is ~EUR 0.44/mo, i.e. cents for an hour. `tofu destroy` removes the
instance, its security group, and the dynamic IP.
