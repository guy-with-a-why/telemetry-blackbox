#!/usr/bin/env bash
# Runs on the server. Deploys ClickHouse on data-1's own disk: the volume, its
# directory on the node, the password Secret, then the server. Safe to run
# again. Each wait that fails says why, rather than ending on a bare timeout.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

kubeconfig=$HOME/.kube/blackbox.conf
if [[ ! -f $kubeconfig ]]; then
  echo "no $kubeconfig; run just cluster-up" >&2
  exit 1
fi
kubectl=(kubectl --kubeconfig "$kubeconfig")
pv() { "${kubectl[@]}" get pv clickhouse -o jsonpath="{$1}"; }

"${kubectl[@]}" apply -f deploy/namespace.yaml -f deploy/storage/local.yaml \
  -f deploy/clickhouse/volume.yaml >/dev/null

if [[ $(pv .status.phase) == Released ]]; then
  echo "pv/clickhouse is Released and won't bind again; free it, then run this again:" >&2
  echo "  kubectl patch pv clickhouse --type json -p '[{\"op\": \"remove\", \"path\": \"/spec/claimRef/uid\"}]'" >&2
  exit 1
fi

# The image runs ClickHouse as uid 101, like Redpanda.
path=$(pv .spec.local.path)
node=$(pv '.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[?(@.key=="kubernetes.io/hostname")].values[0]')
if [[ -z $path || " ${node_names[*]} " != *" $node "* ]]; then
  echo "pv/clickhouse needs a local path and a hostname affinity on one of: ${node_names[*]}" >&2
  exit 1
fi
multipass exec "$node" -- sudo install -d -o 101 -g 101 -m 0750 "$path"

# The password is made here, once, and never reaches the repo. A second run
# keeps the first password, so clients don't lose access. It's made on its
# own line, so set -e stops the script if openssl fails, and goes in on stdin,
# so it never shows in a process list.
if ! "${kubectl[@]}" -n blackbox get secret clickhouse >/dev/null 2>&1; then
  password=$(openssl rand -hex 24)
  printf %s "$password" | "${kubectl[@]}" -n blackbox create secret generic clickhouse \
    --from-file=password=/dev/stdin >/dev/null
  unset password
fi

# The config is mounted by subPath, which the kubelet never refreshes. Its
# hash on the Pod template means a changed ConfigMap rolls the Pod, and an
# unchanged one leaves it alone.
"${kubectl[@]}" apply -f deploy/clickhouse/clickhouse.yaml >/dev/null
hash=$("${kubectl[@]}" -n blackbox get configmap clickhouse-config -o jsonpath='{.data}' | sha256sum | cut -c1-16)
"${kubectl[@]}" -n blackbox patch statefulset clickhouse --type merge \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"blackbox/config-hash\":\"$hash\"}}}}}" >/dev/null
if ! "${kubectl[@]}" -n blackbox rollout status statefulset/clickhouse --timeout 5m; then
  "${kubectl[@]}" -n blackbox get pvc data-clickhouse-0 >&2 || true
  "${kubectl[@]}" -n blackbox events --for pod/clickhouse-0 >&2 || true
  exit 1
fi
# shellcheck disable=SC2016 # expanded in the Pod, where the password lives
"${kubectl[@]}" -n blackbox exec clickhouse-0 -- bash -c 'clickhouse-client --password "$CLICKHOUSE_PASSWORD" \
  --query "SELECT version() AS version, formatReadableSize(free_space) AS free, formatReadableSize(keep_free_space) AS kept FROM system.disks FORMAT PrettyCompact"'
