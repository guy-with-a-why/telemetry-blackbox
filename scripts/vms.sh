#!/usr/bin/env bash
# Usage: vms.sh [create|delete]
# Creates the cluster VMs from deploy/vms/node.yaml, or deletes them. It's safe
# to run again: VMs that already exist are left alone.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

exists() { multipass info "$1" >/dev/null 2>&1; }

# Prints node.yaml with its placeholders filled in, given the host's address.
user_data() {
  sed -e "s/@KUBERNETES_MINOR@/$kubernetes_minor/g" \
    -e "s/@REGISTRY@/$1:$registry_port/g" \
    -e "s/@K8S_MIRROR@/$1:$k8s_mirror_port/g" \
    -e "s/@APT_CACHE@/$1:$apt_cache_port/g" \
    deploy/vms/node.yaml
}

# Waits for cloud-init. Exit code 2 means it finished with warnings.
wait_ready() {
  local status=0
  multipass exec "$1" -- cloud-init status --wait >/dev/null || status=$?
  if ((status != 0 && status != 2)); then
    echo "$1: cloud-init failed; see /var/log/cloud-init-output.log" >&2
    exit 1
  fi
  echo "$1 ready"
}

create() {
  local host node name cpus memory disk
  host=$(scripts/host.sh)
  for node in "${nodes[@]}"; do
    read -r name cpus memory disk <<<"$node"
    if exists "$name"; then
      echo "$name exists"
    else
      # Launch waits for cloud-init, which installs packages, so allow 15 minutes.
      user_data "$host" |
        multipass launch "$release" --name "$name" --zone "$zone" \
          --cpus "$cpus" --memory "$memory" --disk "$disk" \
          --cloud-init - --timeout 900
    fi
    wait_ready "$name"
  done
}

delete() {
  local name
  for name in "${node_names[@]}"; do
    if exists "$name"; then multipass delete --purge "$name"; fi
  done
}

case ${1:-create} in
  create) create ;;
  delete) delete ;;
  *)
    echo "usage: $0 [create|delete]" >&2
    exit 2
    ;;
esac
