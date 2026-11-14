#!/usr/bin/env bash
# Checks the cluster: no VM leases the VIP, the API answers on it with the
# cluster's certificate, every node is Ready, etcd is healthy on every control
# plane and Cilium runs on every node. It asks the first control plane whose
# own API server is ready, not the VIP, so it still reports mid-drill.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

failed=0
fail() {
  echo "$*" >&2
  failed=1
}

# Column 3 is the address each VM leased.
if multipass list --format csv | awk -F, -v vip="$vip" '$3 == vip { found = 1 } END { exit !found }'; then
  fail "a VM leases the VIP $vip"
fi

# kubectl on a node, talking to that node's API server rather than the VIP.
# The serving certificate names 127.0.0.1.
local_kubectl() {
  multipass exec "$1" -- sudo kubectl --kubeconfig /etc/kubernetes/admin.conf \
    --server https://127.0.0.1:6443 "${@:2}"
}

# /readyz includes the node's etcd, so a node that passes can answer the rest.
via=
for name in "${control_planes[@]}"; do
  if local_kubectl "$name" get --raw /readyz >/dev/null 2>&1; then
    via=$name
    break
  fi
done
if [[ -z $via ]]; then
  echo "no control plane's API server is ready; has kubeadm init run?" >&2
  exit 1
fi
kubectl() { local_kubectl "$via" "$@"; }

# Verify against the cluster's CA, so a stray server on the VIP can't pass.
ca=$(multipass exec "$via" -- sudo cat /etc/kubernetes/pki/ca.crt)
if livez=$(curl -fsS --max-time 5 --cacert <(echo "$ca") "https://$vip:6443/livez"); then
  holder=$(kubectl -n kube-system get lease "$kube_vip_lease" -o jsonpath='{.spec.holderIdentity}' || true)
  echo "API on $vip: $livez, held by $holder"
else
  fail "the API doesn't answer on $vip"
fi

ready=$(kubectl get nodes --no-headers | awk '$2 == "Ready"' | wc -l || true)
if ((ready == ${#node_names[@]})); then
  echo "nodes: $ready of ${#node_names[@]} Ready"
else
  fail "nodes: $ready of ${#node_names[@]} Ready"
fi

# member list only shows membership, so ask every member whether it serves.
healthy=$(kubectl -n kube-system exec "etcd-$via" -- etcdctl \
  --endpoints https://127.0.0.1:2379 --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key /etc/kubernetes/pki/etcd/healthcheck-client.key \
  endpoint health --cluster 2>&1 | grep -c ' is healthy:' || true)
if ((healthy == ${#control_planes[@]})); then
  echo "etcd: $healthy of ${#control_planes[@]} members healthy"
else
  fail "etcd: $healthy of ${#control_planes[@]} members healthy"
fi

cilium=$(kubectl -n kube-system get daemonset cilium \
  -o jsonpath='{.status.numberReady}' 2>/dev/null || true)
cilium=${cilium:-0}
if ((cilium == ${#node_names[@]})); then
  echo "cilium: ready on $cilium nodes"
else
  fail "cilium: ready on $cilium of ${#node_names[@]} nodes"
fi
exit "$failed"
