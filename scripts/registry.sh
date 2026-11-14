#!/usr/bin/env bash
# Runs the local image registry and prints the address the VMs reach it on.
# It listens on localhost, where Docker pushes without TLS, and on the
# Multipass bridge, where containerd on every VM pulls from it.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

name=blackbox-registry
image=registry:2.8.3@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373

ip=$(ip -4 -o addr show dev "$bridge" 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4 }')
if [[ -z $ip ]]; then
  echo "registry: $bridge has no IPv4 address; is Multipass running?" >&2
  exit 1
fi

running=$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)
case $running in
  true) ;;
  false) docker start "$name" >/dev/null ;;
  *)
    docker run -d --name "$name" --restart unless-stopped \
      -p "127.0.0.1:$registry_port:5000" -p "$ip:$registry_port:5000" \
      -v "$name:/var/lib/registry" "$image" >/dev/null
    ;;
esac

echo "$ip:$registry_port"
