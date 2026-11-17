#!/usr/bin/env bash
# Takes a snapshot of etcd and copies it to the host, in
# ~/.local/state/telemetry-blackbox/etcd/. It runs etcdctl inside the etcd
# container of the first running control plane, through crictl rather than the
# API, so it works while the API is down. A snapshot is one member's own
# database, so it doesn't need quorum either. It never starts a stopped VM.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

dir=${XDG_STATE_HOME:-$HOME/.local/state}/telemetry-blackbox/etcd

# multipass exec starts a stopped VM, which would undo a drill, so only ask the
# control planes that are running.
mapfile -t running < <(multipass list --format csv | awk -F, '$1 ~ /^cp-/ && $2 == "Running" { print $1 }')

via=''
id=''
for name in "${running[@]}"; do
  id=$(multipass exec "$name" -- sudo crictl ps -q --state running --name '^etcd$' 2>/dev/null || true)
  if [[ -n $id ]]; then
    via=$name
    break
  fi
done
if [[ -z $via ]]; then
  echo "no running control plane has a running etcd (running: ${running[*]:-none})" >&2
  exit 1
fi

# The etcd Pod mounts /var/lib/etcd from the node, so a file written there
# inside the container can be read from the node.
in_etcd() { multipass exec "$via" -- sudo crictl exec "$id" "$@"; }
on_node() { multipass exec "$via" -- sudo "$@"; }

stamp=$(date -u +%Y%m%dT%H%M%SZ)
remote=/var/lib/etcd/snapshot-$stamp.db
local=$dir/etcd-$stamp.db
trap 'on_node rm -f "$remote" "$remote.part" || true; rm -f "$local.part"' EXIT

# etcdctl logs as JSON on stderr, so show it only if the save fails.
if ! log=$(in_etcd etcdctl --endpoints https://127.0.0.1:2379 \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key /etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save "$remote" 2>&1); then
  echo "$log" >&2
  exit 1
fi

# etcd 3.6 moved status from etcdctl to etcdutl. It reads the file, not the
# member, and fails if the file is torn.
status=$(in_etcd etcdutl snapshot status "$remote" --write-out table)

# A snapshot holds every Secret in the cluster in plain text, so only I can
# read it.
umask 077
mkdir -p "$dir"
on_node cat "$remote" >"$local.part"
want=$(on_node sha256sum "$remote" | awk '{ print $1 }')
got=$(sha256sum "$local.part" | awk '{ print $1 }')
if [[ $want != "$got" ]]; then
  echo "the copy of $remote doesn't match the original" >&2
  exit 1
fi
mv "$local.part" "$local"

echo "snapshot of etcd on $via: $local"
echo "sha256: $got"
echo "$status"
