#!/usr/bin/env bash
# Checks every VM is ready for kubeadm: the right version, no swap, the
# kernel settings, apt going through the host's cache and containerd pulling
# from the local registry and the registry.k8s.io mirror.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

host=$(scripts/host.sh)
busybox=busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec
probe=localhost:$registry_port/busybox:check

# Push a small image from the host, so each node has something to pull.
docker pull -q "$busybox" >/dev/null
docker tag "$busybox" "$probe"
docker push -q "$probe" >/dev/null

# Runs on the node. Prints the kubeadm version, or the first check that failed.
check_node() {
  multipass exec "$1" -- sudo bash -s "$kubernetes_minor" "$probe" "$host:$apt_cache_port" <<'EOF'
set -euo pipefail
minor=$1 probe=$2 apt_cache=$3
fail() { echo "$*"; exit 1; }

version=$(kubeadm version -o short)
[[ $version == "$minor".* ]] || fail "kubeadm is $version"
[[ -z $(swapon --show) ]] || fail "swap is on"
for key in net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables; do
  [[ $(sysctl -n "$key") == 1 ]] || fail "$key is not 1"
done
grep -rqF "http://$apt_cache/" /etc/apt/sources.list.d || fail "apt skips the cache"
systemctl is-active -q containerd || fail "containerd is down"
crictl pull "$probe" >/dev/null || fail "can't pull $probe"
# Every pod starts with pause, so no pause means no pods. It comes from
# registry.k8s.io, so pulling it also tests the mirror.
pause=$(kubeadm config images list --kubernetes-version "$version" | grep /pause:)
crictl pull "$pause" >/dev/null || fail "can't pull $pause"
echo "$version"
EOF
}

failed=0
for name in "${node_names[@]}"; do
  if out=$(check_node "$name" 2>&1); then
    echo "$name ok, kubeadm $out"
  else
    echo "$name failed: $out" >&2
    failed=1
  fi
done

# The nodes pulled pause from registry.k8s.io, so the mirror should hold it.
if ! curl -fsS "http://$host:$k8s_mirror_port/v2/_catalog" | grep -q pause; then
  echo "the registry.k8s.io mirror served nothing" >&2
  failed=1
fi
exit "$failed"
