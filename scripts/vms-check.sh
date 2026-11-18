#!/usr/bin/env bash
# Checks every VM is ready for kubeadm: the right version, no swap, the
# kernel settings, apt going through the host's cache and containerd pulling
# from the local registry and the mirrors of registry.k8s.io, quay.io,
# ghcr.io and Docker Hub.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

host=$(scripts/host.sh)
busybox=busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec
probe=localhost:$registry_port/busybox:check
# Small images that only the quay.io, ghcr.io and Docker Hub mirrors can serve.
quay_probe=quay.io/prometheus/busybox:latest@sha256:7379672d53c28113469275f2eb48adffa19954f39f8ef20c1e2992278f658e6c
ghcr_probe=ghcr.io/containerd/busybox:1.36@sha256:7b3ccabffc97de872a30dfd234fd972a66d247c8cfc69b0550f276481852627c
dockerhub_probe=docker.io/library/$busybox

# Push a small image from the host, so each node has something to pull.
docker pull -q "$busybox" >/dev/null
docker tag "$busybox" "$probe"
docker push -q "$probe" >/dev/null

# Runs on the node. Prints the kubeadm version, or the first check that failed.
check_node() {
  multipass exec "$1" -- sudo bash -s "$kubernetes_minor" "$host:$apt_cache_port" \
    "$probe" "$quay_probe" "$ghcr_probe" "$dockerhub_probe" <<'EOF'
set -euo pipefail
minor=$1 apt_cache=$2
shift 2
fail() { echo "$*"; exit 1; }

version=$(kubeadm version -o short)
[[ $version == "$minor".* ]] || fail "kubeadm is $version"
[[ -z $(swapon --show) ]] || fail "swap is on"
for key in net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables; do
  [[ $(sysctl -n "$key") == 1 ]] || fail "$key is not 1"
done
grep -rqF "http://$apt_cache/" /etc/apt/sources.list.d || fail "apt skips the cache"
systemctl is-active -q containerd || fail "containerd is down"
for image in "$@"; do
  crictl pull "$image" >/dev/null || fail "can't pull $image"
done
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

# Each mirror should now hold what the nodes pulled through it, which proves
# containerd went through the mirror and not straight upstream.
for mirror in "registry.k8s.io $k8s_mirror_port pause" \
  "quay.io $quay_mirror_port prometheus/busybox" \
  "ghcr.io $ghcr_mirror_port containerd/busybox" \
  "docker.io $dockerhub_mirror_port library/busybox"; do
  read -r upstream port repo <<<"$mirror"
  if ! curl -fsS "http://$host:$port/v2/_catalog" | grep -qF "\"$repo\""; then
    echo "the $upstream mirror didn't serve $repo" >&2
    failed=1
  fi
done
exit "$failed"
