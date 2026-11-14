#!/usr/bin/env bash
# Runs what the VMs use from the host, and prints the host's address on the
# Multipass bridge:
#   - the image registry, on localhost for pushes and the bridge for pulls
#   - an apt cache, so each package crosses the internet once
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

registry_image=registry:2.8.3@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373

ip=$(ip -4 -o addr show dev "$bridge" 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4 }')
if [[ -z $ip ]]; then
  echo "host: $bridge has no IPv4 address; is Multipass running?" >&2
  exit 1
fi

# Starts a container unless it's already running. The arguments after the
# name are passed to docker run.
ensure() {
  local name=$1
  shift
  case $(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true) in
    true) ;;
    false) docker start "$name" >/dev/null ;;
    *) docker run -d --name "$name" --restart unless-stopped "$@" >/dev/null ;;
  esac
}

ensure blackbox-registry \
  -p "127.0.0.1:$registry_port:5000" -p "$ip:$registry_port:5000" \
  -v blackbox-registry:/var/lib/registry "$registry_image"

docker build -q -t blackbox-apt-cache deploy/apt-cache >/dev/null
ensure blackbox-apt-cache \
  -p "$ip:$apt_cache_port:3142" \
  -v blackbox-apt-cache:/var/cache/apt-cacher-ng blackbox-apt-cache

echo "$ip"
