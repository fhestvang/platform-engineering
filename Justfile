set shell := ["bash", "-cu"]

scw_instance_dir := "provisioning/scw-instance"

default:
    @just --list

# Prepare local-only bootstrap inputs for a Scaleway instance.
scw-instance-prepare hostname:
    #!/usr/bin/env bash
    set -euo pipefail
    hostname='{{hostname}}'
    case "$hostname" in
      scw-instance-*) ;;
      *) echo "ERROR: hostname must start with scw-instance-" >&2; exit 1 ;;
    esac

    for cmd in bao curl jq; do
      command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing $cmd" >&2; exit 1; }
    done

    export BAO_ADDR="${BAO_ADDR:-https://bao.olm-hops.ts.net}"
    work_dir='{{scw_instance_dir}}'
    generated_dir="$work_dir/.generated"
    mkdir -p "$generated_dir"

    ssh_pubkey_path="${FLEET_OPERATOR_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
    [ -r "$ssh_pubkey_path" ] || { echo "ERROR: SSH public key not readable: $ssh_pubkey_path" >&2; exit 1; }

    tailscale_secret_path="${FLEET_TAILSCALE_BAO_PATH:-kv/projects/fos/shared/tailscale-admin}"
    tailscale_tag="${FLEET_BOOTSTRAP_TAILSCALE_TAG:-tag:scw-instance}"
    tailscale_api_key="$(bao kv get -field=TAILSCALE_API_KEY "$tailscale_secret_path")"
    tailscale_api_base="$(bao kv get -field=TAILSCALE_API_BASE "$tailscale_secret_path" 2>/dev/null || true)"
    tailscale_tailnet="$(bao kv get -field=TAILSCALE_TAILNET "$tailscale_secret_path" 2>/dev/null || true)"
    tailscale_api_base="${tailscale_api_base:-https://api.tailscale.com/api/v2}"
    tailscale_tailnet="${tailscale_tailnet:--}"

    auth_body="$(
      jq -n \
        --arg tag "$tailscale_tag" \
        --arg desc "$hostname-cloud-init-$(date -u +%Y%m%dT%H%M%SZ)" \
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

    auth_response="$(mktemp)"
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
      rm -f "$auth_response"
      exit 1
    fi
    tailscale_auth_key="$(jq -r '.key' "$auth_response")"
    auth_key_id="$(jq -r '.id' "$auth_response")"
    rm -f "$auth_response"

    fleet_role="${FLEET_BAO_APPROLE:-fleet-kv}"
    role_id="$(bao read -field=role_id "auth/approle/role/${fleet_role}/role-id")"
    secret_id="$(bao write -f -field=secret_id "auth/approle/role/${fleet_role}/secret-id")"
    approle_content="$(printf 'VAULT_ROLE_ID=%s\nVAULT_SECRET_ID=%s\n' "$role_id" "$secret_id")"

    tfvars="$generated_dir/$hostname.auto.tfvars.json"
    jq -n \
      --arg hostname "$hostname" \
      --arg operator_ssh_public_key "$(cat "$ssh_pubkey_path")" \
      --arg tailscale_auth_key "$tailscale_auth_key" \
      --arg bao_approle_content "$approle_content" \
      '{
        hostname: $hostname,
        operator_ssh_public_key: $operator_ssh_public_key,
        tailscale_auth_key: $tailscale_auth_key,
        bao_approle_content: $bao_approle_content
      }' > "$tfvars"
    chmod 600 "$tfvars"
    echo "Wrote $tfvars"
    echo "Created one-use Tailscale auth key $auth_key_id for $tailscale_tag"
    echo "Apply within one hour, or rerun this recipe."

# Run OpenTofu in the Scaleway instance root module with Scaleway credentials from Bao.
scw-instance-tofu *args:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v tofu >/dev/null 2>&1 || { echo "ERROR: missing tofu" >&2; exit 1; }
    command -v bao >/dev/null 2>&1 || { echo "ERROR: missing bao" >&2; exit 1; }
    export BAO_ADDR="${BAO_ADDR:-https://bao.olm-hops.ts.net}"
    scw_config_dir="$(mktemp -d)"
    trap 'rm -rf "$scw_config_dir"' EXIT
    : > "$scw_config_dir/config.yaml"
    export SCW_CONFIG_PATH="$scw_config_dir/config.yaml"
    export SCW_ACCESS_KEY="$(bao kv get -field=access_key kv/projects/scaleway/cli)"
    export SCW_SECRET_KEY="$(bao kv get -field=secret_key kv/projects/scaleway/cli)"
    unset SCW_DEFAULT_PROJECT_ID SCW_DEFAULT_REGION SCW_DEFAULT_ZONE
    tofu -chdir='{{scw_instance_dir}}' {{args}}

# Initialize the Scaleway instance OpenTofu root module.
scw-instance-init:
    just scw-instance-tofu init

# Create a reviewed plan for a new Scaleway instance.
scw-instance-plan hostname:
    just scw-instance-prepare {{hostname}}
    just scw-instance-tofu plan -var-file=.generated/{{hostname}}.auto.tfvars.json -out=.generated/{{hostname}}.tfplan

# Apply the saved plan for a new Scaleway instance.
scw-instance-apply hostname:
    just scw-instance-tofu apply .generated/{{hostname}}.tfplan

# Create a new Scaleway instance from prepare -> plan -> apply.
scw-instance-create hostname:
    just scw-instance-plan {{hostname}}
    just scw-instance-apply {{hostname}}

# Verify a converged Scaleway instance over the tailnet.
scw-instance-verify hostname:
    #!/usr/bin/env bash
    set -euo pipefail
    hostname='{{hostname}}'
    tailscale ping --until-direct=false --c 1 "$hostname"
    tailscale_ip="$(
      tailscale status --json \
        | jq -r --arg hostname "$hostname" '.Peer[]? | select(.HostName == $hostname) | .TailscaleIPs[0]' \
        | head -n1
    )"
    [ -n "$tailscale_ip" ] && [ "$tailscale_ip" != "null" ] || {
      echo "ERROR: $hostname is not visible in Tailscale status" >&2
      exit 1
    }
    ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "fhestvang@$tailscale_ip" 'set -euo pipefail; export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"; export BAO_ADDR="${BAO_ADDR:-https://bao.olm-hops.ts.net}"; export VAULT_ADDR="$BAO_ADDR"; hostname; whoami; chezmoi data | grep -E "hostname|role|hasFhhToolkit"; for c in mise node nvim lazygit starship fzf zoxide fd rg bat eza atuin direnv yazi tmux sesh btop gh gh-dash kubectl k9s k3d dagger skaffold glow lazydocker codex claude pi; do printf "%s=" "$c"; command -v "$c"; done; bao kv get -field=GITHUB_TOKEN kv/projects/fos/shared/github-cli >/dev/null; test -d ~/github/fhh-toolkit/.git; crontab -l | grep chezmoi-sync'
