#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/bootstrap-scaleway-agent.sh <public-ssh-host> <scw-agent-hostname>

Example:
  scripts/bootstrap-scaleway-agent.sh 151.115.73.73 scw-agent-02

What it does:
  - creates a one-use, one-hour Tailscale auth key tagged tag:scw-agent
  - creates fresh fleet-kv AppRole material for the VM
  - SSHes to the VM as root
  - creates/repairs the fhestvang user and SSH key
  - joins Tailscale with --ssh, --accept-dns=true, and the scw-agent hostname
  - runs chezmoi init/update as fhestvang
  - verifies Bao, fhh-toolkit, mise shims, and agent commands

Prerequisites on the operator machine:
  bao, curl, jq, ssh, and access to:
    kv/projects/fos/shared/tailscale-admin
    auth/approle/role/fleet-kv
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

public_host="$1"
agent_hostname="$2"

case "$agent_hostname" in
  scw-*) ;;
  *)
    echo "ERROR: hostname must start with scw- so chezmoi renders role=scw-agent" >&2
    exit 1
    ;;
esac

operator_user="${FLEET_BOOTSTRAP_USER:-fhestvang}"
root_ssh_user="${FLEET_BOOTSTRAP_ROOT_USER:-root}"
ssh_pubkey="${FLEET_BOOTSTRAP_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
tailscale_tag="${FLEET_BOOTSTRAP_TAILSCALE_TAG:-tag:scw-agent}"
bao_addr="${BAO_ADDR:-https://bao.olm-hops.ts.net}"
tailscale_secret_path="${FLEET_TAILSCALE_BAO_PATH:-kv/projects/fos/shared/tailscale-admin}"
fleet_role="${FLEET_BAO_APPROLE:-fleet-kv}"

for cmd in bao curl jq ssh; do
  require_cmd "$cmd"
done

if [[ ! -r "$ssh_pubkey" ]]; then
  echo "ERROR: SSH public key not readable: $ssh_pubkey" >&2
  exit 1
fi

export BAO_ADDR="$bao_addr"

tmp_dir="$(mktemp -d)"
auth_key_id=""

cleanup() {
  rm -rf "$tmp_dir"
  if [[ -n "$auth_key_id" ]]; then
    curl -fsSL -u "${tailscale_api_key}:" -X DELETE \
      "${tailscale_api_base%/}/tailnet/${tailscale_tailnet}/keys/${auth_key_id}" \
      >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

tailscale_api_key="$(bao kv get -field=TAILSCALE_API_KEY "$tailscale_secret_path")"
tailscale_api_base="$(bao kv get -field=TAILSCALE_API_BASE "$tailscale_secret_path" 2>/dev/null || true)"
tailscale_tailnet="$(bao kv get -field=TAILSCALE_TAILNET "$tailscale_secret_path" 2>/dev/null || true)"
tailscale_api_base="${tailscale_api_base:-https://api.tailscale.com/api/v2}"
tailscale_tailnet="${tailscale_tailnet:--}"

if [[ ! "$tailscale_api_key" =~ ^tskey-api- ]]; then
  echo "ERROR: Tailscale API key is missing or invalid in $tailscale_secret_path" >&2
  exit 1
fi

auth_body="$(
  jq -n \
    --arg tag "$tailscale_tag" \
    --arg desc "$agent_hostname-bootstrap-$(date -u +%Y%m%dT%H%M%SZ)" \
    '{
      capabilities: {
        devices: {
          create: {
            reusable: false,
            ephemeral: false,
            preauthorized: true,
            tags: [$tag]
          }
        }
      },
      expirySeconds: 3600,
      description: $desc
    }'
)"

auth_response="$tmp_dir/tailscale-authkey.json"
http_code="$(
  curl -sS -o "$auth_response" -w '%{http_code}' \
    -u "${tailscale_api_key}:" \
    -H 'Content-Type: application/json' \
    -X POST "${tailscale_api_base%/}/tailnet/${tailscale_tailnet}/keys" \
    -d "$auth_body"
)"

if [[ "$http_code" != "200" ]]; then
  echo "ERROR: could not create Tailscale auth key (HTTP $http_code)" >&2
  jq -r '.message // .error // .' "$auth_response" >&2 || cat "$auth_response" >&2
  exit 1
fi

auth_key_id="$(jq -r '.id' "$auth_response")"
jq -r '.key' "$auth_response" > "$tmp_dir/tailscale-authkey"
chmod 600 "$tmp_dir/tailscale-authkey"
echo "Created one-use Tailscale auth key $auth_key_id for $tailscale_tag"

role_id="$(bao read -field=role_id "auth/approle/role/${fleet_role}/role-id")"
secret_id="$(bao write -f -field=secret_id "auth/approle/role/${fleet_role}/secret-id")"
{
  printf 'VAULT_ROLE_ID=%q\n' "$role_id"
  printf 'VAULT_SECRET_ID=%q\n' "$secret_id"
} > "$tmp_dir/approle"
chmod 600 "$tmp_dir/approle"

cp "$ssh_pubkey" "$tmp_dir/ssh.pub"

cat > "$tmp_dir/remote-bootstrap.sh" <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail

bootstrap_dir="$1"
agent_hostname="$2"
operator_user="$3"

export DEBIAN_FRONTEND=noninteractive

hostnamectl set-hostname "$agent_hostname"
apt-get update
apt-get install -y curl git ca-certificates sudo openssh-server

if ! id -u "$operator_user" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$operator_user"
fi
usermod -aG sudo "$operator_user"

home_dir="$(getent passwd "$operator_user" | cut -d: -f6)"
install -d -m 700 -o "$operator_user" -g "$operator_user" "$home_dir/.ssh"
touch "$home_dir/.ssh/authorized_keys"
grep -qxF "$(cat "$bootstrap_dir/ssh.pub")" "$home_dir/.ssh/authorized_keys" \
  || cat "$bootstrap_dir/ssh.pub" >> "$home_dir/.ssh/authorized_keys"
chown "$operator_user:$operator_user" "$home_dir/.ssh/authorized_keys"
chmod 600 "$home_dir/.ssh/authorized_keys"

# Non-interactive chezmoi convergence needs sudo for apt-backed base packages.
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$operator_user" >/etc/sudoers.d/90-fleet-bootstrap
chmod 440 /etc/sudoers.d/90-fleet-bootstrap

if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
systemctl enable --now tailscaled
# A repair run on an already-joined VM must drop the old user-owned identity
# before the tagged auth key can take effect. The script connects over public
# SSH, so briefly leaving the tailnet here is acceptable.
tailscale logout >/dev/null 2>&1 || true
tailscale up --reset \
  --auth-key="$(cat "$bootstrap_dir/tailscale-authkey")" \
  --ssh \
  --accept-dns=true \
  --hostname="$agent_hostname"

install -d -m 700 -o "$operator_user" -g "$operator_user" "$home_dir/.config/bao"
install -m 600 -o "$operator_user" -g "$operator_user" "$bootstrap_dir/approle" "$home_dir/.config/bao/approle"

install -d -m 700 -o "$operator_user" -g "$operator_user" "$home_dir/.cache/fleet-bootstrap"
converge_script="$home_dir/.cache/fleet-bootstrap/chezmoi-converge.sh"
cat >"$converge_script" <<'CONVERGE'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.local/bin"
if [ ! -x "$HOME/.local/bin/chezmoi" ]; then
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
fi

if [ -d "$HOME/.local/share/chezmoi/.git" ]; then
  "$HOME/.local/bin/chezmoi" --force update
else
  "$HOME/.local/bin/chezmoi" --force init --apply https://github.com/fhestvang/fleet-provisioning.git
fi
CONVERGE
chown "$operator_user:$operator_user" "$converge_script"
chmod 700 "$converge_script"

sudo -iu "$operator_user" "$converge_script"

rm -rf "$bootstrap_dir"
REMOTE
chmod 700 "$tmp_dir/remote-bootstrap.sh"

remote="root@${public_host}"
if [[ "$root_ssh_user" != "root" ]]; then
  remote="${root_ssh_user}@${public_host}"
fi

remote_dir="/tmp/fleet-bootstrap-${agent_hostname}-$$"
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$remote" \
  "rm -rf '$remote_dir' && install -d -m 700 '$remote_dir'"

for file in tailscale-authkey approle ssh.pub remote-bootstrap.sh; do
  ssh -o BatchMode=yes "$remote" "cat > '$remote_dir/$file'" < "$tmp_dir/$file"
done
ssh -o BatchMode=yes "$remote" "chmod 700 '$remote_dir/remote-bootstrap.sh'; chmod 600 '$remote_dir/tailscale-authkey' '$remote_dir/approle'"

ssh -o BatchMode=yes "$remote" "bash '$remote_dir/remote-bootstrap.sh' '$remote_dir' '$agent_hostname' '$operator_user'"

echo "Verifying $agent_hostname..."
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${operator_user}@${public_host}" \
  "zsh -lc 'set -e; chezmoi data | grep -E \"hostname|role|isAgentHost\"; for c in mise node nvim lazygit codex claude pi; do printf \"%s=\" \"\$c\"; command -v \"\$c\"; done; bao kv get -field=GITHUB_TOKEN kv/projects/fos/shared/github-cli >/dev/null; test -d ~/github/fhh-toolkit/.git; crontab -l | grep chezmoi-sync'"

echo "Done. Tailnet check:"
tailscale ping --c 1 "$agent_hostname" || true
