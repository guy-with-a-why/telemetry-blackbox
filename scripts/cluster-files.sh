#!/usr/bin/env bash
# Renders deploy/cluster/ for this cluster and copies it to ~/cluster/ on the
# control planes: kubeadm.yaml to cp-1, kube-vip.yaml to all three. It doesn't
# touch /etc/kubernetes. Moving the files into place is part of the bootstrap.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

first=${control_planes[0]}

# A VM holding the VIP would answer for it instead of kube-vip. Column 3 is
# the address each VM leased.
if multipass list --format csv | awk -F, -v vip="$vip" '$3 == vip { found = 1 } END { exit !found }'; then
  echo "a VM leases the VIP $vip; pick another in deploy/vms/config.sh" >&2
  exit 1
fi

version=$(multipass exec "$first" -- kubeadm version -o short)

# Prints a file with its placeholders filled in, and fails on any left over.
# The second argument is the interface kube-vip announces the VIP on.
render() {
  local out left
  out=$(sed -e "s/@KUBERNETES_VERSION@/$version/g" \
    -e "s/@VIP@/$vip/g" \
    -e "s#@POD_SUBNET@#$pod_subnet#g" \
    -e "s#@SERVICE_SUBNET@#$service_subnet#g" \
    -e "s/@INTERFACE@/${2-}/g" \
    -e "s#@IMAGE@#$kube_vip_image#g" \
    -e "s/@LEASE@/$kube_vip_lease/g" \
    "$1")
  if left=$(grep -oE '@[A-Z0-9_]+@' <<<"$out" | sort -u); then
    echo "$1: nothing fills ${left//$'\n'/ }" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

# The host's address on the bridge, which shares a subnet with the VIP.
host_ip=$(ip -4 -o addr show dev "$bridge" 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4; exit }' || true)
if [[ -z $host_ip ]]; then
  echo "$bridge has no IPv4 address; is Multipass running?" >&2
  exit 1
fi

# Prints the interface a node uses to reach the bridge, where the VIP lives.
# Asking for the VIP's own route fails on the node that holds it, which
# answers "local <vip> dev lo".
interface() {
  local dev
  dev=$(multipass exec "$1" -- ip -o -4 route get "$host_ip" |
    awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
  if [[ -z $dev ]]; then
    echo "$1: no route to the bridge at $host_ip" >&2
    return 1
  fi
  echo "$dev"
}

# Writes stdin to ~/cluster/<file> on a node.
put() {
  multipass exec "$1" -- bash -c "mkdir -p ~/cluster && cat >~/cluster/$2"
  echo "$1: ~/cluster/$2"
}

# Render everything before copying anything, so a bad template copies nothing.
kubeadm=$(render deploy/cluster/kubeadm.yaml)
declare -A kube_vip
for name in "${control_planes[@]}"; do
  dev=$(interface "$name")
  kube_vip[$name]=$(render deploy/cluster/kube-vip.yaml "$dev")
done
put "$first" kubeadm.yaml <<<"$kubeadm"
for name in "${control_planes[@]}"; do put "$name" kube-vip.yaml <<<"${kube_vip[$name]}"; done
