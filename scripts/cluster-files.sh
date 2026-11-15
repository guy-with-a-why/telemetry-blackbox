#!/usr/bin/env bash
# Usage: cluster-files.sh [init|join]
# Renders deploy/cluster/ for this cluster and copies it to ~/cluster/ on the
# nodes. It doesn't touch /etc/kubernetes. Moving the files into place is part
# of the bootstrap.
#
#   init   kubeadm.yaml to cp-1 and kube-vip.yaml to all three control planes.
#          It takes BOOTSTRAP_TOKEN and CERTIFICATE_KEY from the environment,
#          or makes fresh ones.
#   join   join.yaml to every other node, for its role. It needs the
#          BOOTSTRAP_TOKEN and CERTIFICATE_KEY init used, and runs after init,
#          once cp-1 has the CA whose hash the joins check.
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

# Prints a file with its placeholders filled in, and fails on any left over.
# The second argument is the interface kube-vip announces the VIP on.
render() {
  local out left
  out=$(sed -e "s/@KUBERNETES_VERSION@/${version-}/g" \
    -e "s/@VIP@/$vip/g" \
    -e "s#@POD_SUBNET@#$pod_subnet#g" \
    -e "s#@SERVICE_SUBNET@#$service_subnet#g" \
    -e "s/@INTERFACE@/${2-}/g" \
    -e "s#@IMAGE@#$kube_vip_image#g" \
    -e "s/@LEASE@/$kube_vip_lease/g" \
    -e "s/@TOKEN@/$BOOTSTRAP_TOKEN/g" \
    -e "s/@CERTIFICATE_KEY@/$CERTIFICATE_KEY/g" \
    -e "s/@CA_HASH@/${CA_HASH-}/g" \
    "$1")
  if left=$(grep -oE '@[A-Z0-9_]+@' <<<"$out" | sort -u); then
    echo "$1: nothing fills ${left//$'\n'/ }" >&2
    return 1
  fi
  if grep -qF '""' <<<"$out"; then
    echo "$1: a placeholder was filled with nothing" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

# Prints the interface a node uses to reach the host's bridge address, where
# the VIP lives. Asking for the VIP's own route fails on the node that holds
# it, which answers "local <vip> dev lo".
interface() {
  local dev
  dev=$(multipass exec "$1" -- ip -o -4 route get "$2" |
    awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
  if [[ -z $dev ]]; then
    echo "$1: no route to the bridge at $2" >&2
    return 1
  fi
  echo "$dev"
}

# Writes stdin to a file in cluster_dir on a node, readable only by its
# owner, because the files carry the token and the certificate key.
put() {
  multipass exec "$1" -- bash -c "umask 077 && mkdir -p $cluster_dir && cat >$cluster_dir/$2"
  echo "$1: $cluster_dir/$2"
}

init_files() {
  local kubeadm name dev host_ip
  # The token joins nodes for 24 hours and the key unlocks the uploaded
  # certificates for two. kubeadm makes both in the right format.
  : "${BOOTSTRAP_TOKEN:=$(multipass exec "$first" -- kubeadm token generate)}"
  : "${CERTIFICATE_KEY:=$(multipass exec "$first" -- kubeadm certs certificate-key)}"
  version=$(multipass exec "$first" -- kubeadm version -o short)

  # The host's address on the bridge, which shares a subnet with the VIP.
  host_ip=$(ip -4 -o addr show dev "$bridge" 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4; exit }' || true)
  if [[ -z $host_ip ]]; then
    echo "$bridge has no IPv4 address; is Multipass running?" >&2
    exit 1
  fi

  # Render everything before copying anything, so a bad template copies nothing.
  kubeadm=$(render deploy/cluster/kubeadm.yaml)
  declare -A kube_vip
  for name in "${control_planes[@]}"; do
    dev=$(interface "$name" "$host_ip")
    kube_vip[$name]=$(render deploy/cluster/kube-vip.yaml "$dev")
  done
  put "$first" kubeadm.yaml <<<"$kubeadm"
  for name in "${control_planes[@]}"; do put "$name" kube-vip.yaml <<<"${kube_vip[$name]}"; done
}

join_files() {
  local control_plane worker name
  : "${BOOTSTRAP_TOKEN:?join needs the token init used}"
  : "${CERTIFICATE_KEY:?join needs the certificate key init used}"
  # The SHA-256 of the CA's public key. pipefail stops a failed openssl
  # hashing empty input into a hash that looks valid.
  CA_HASH=sha256:$(multipass exec "$first" -- bash -c 'set -o pipefail &&
    openssl x509 -pubkey -noout -in /etc/kubernetes/pki/ca.crt |
    openssl pkey -pubin -outform der | sha256sum' | cut -d' ' -f1)
  control_plane=$(render deploy/cluster/join-control-plane.yaml)
  worker=$(render deploy/cluster/join-worker.yaml)
  for name in "${control_planes[@]:1}"; do put "$name" join.yaml <<<"$control_plane"; done
  for name in "${workers[@]}"; do put "$name" join.yaml <<<"$worker"; done
}

case ${1:-init} in
  init) init_files ;;
  join) join_files ;;
  *)
    echo "usage: $0 [init|join]" >&2
    exit 2
    ;;
esac
