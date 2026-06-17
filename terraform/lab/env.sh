# Source this before tofu. Loads Scaleway API creds from OpenBao into the env
# (the scaleway provider reads SCW_*; project/zone come from ~/.config/scw/
# config.yaml). Usage:  source env.sh
: "${BAO_ADDR:=https://bao.olm-hops.ts.net}"
export BAO_ADDR
export SCW_ACCESS_KEY="$(bao kv get -field=access_key kv/projects/scaleway/cli)"
export SCW_SECRET_KEY="$(bao kv get -field=secret_key kv/projects/scaleway/cli)"
if [ -n "$SCW_ACCESS_KEY" ] && [ -n "$SCW_SECRET_KEY" ]; then
  echo "scw creds loaded (access_key ${SCW_ACCESS_KEY:0:6}…); project/zone from scw config.yaml"
else
  echo "failed to load scw creds from Bao" >&2
fi
