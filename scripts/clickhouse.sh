#!/usr/bin/env bash
# Runs on the server. Deploys ClickHouse on data-1's own disk: the volume, its
# directory on the node, the password Secret, the server, then its tables.
# Safe to run again. Each wait that fails says why, rather than ending on a
# bare timeout.
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
# hash goes on the Pod template before the first apply, so a changed
# ConfigMap rolls the Pod once and an unchanged one leaves it alone.
manifest=deploy/clickhouse/clickhouse.yaml
# The jsonpath runs on each object, and only the ConfigMap has data.
data=$("${kubectl[@]}" create -f "$manifest" --dry-run=client -o jsonpath='{.data}')
if [[ -z $data ]]; then
  echo "no ConfigMap data in $manifest" >&2
  exit 1
fi
hash=$(sha256sum <<<"$data" | cut -c1-16)
sed "s/CONFIG_HASH/$hash/" "$manifest" | "${kubectl[@]}" apply -f - >/dev/null
if ! "${kubectl[@]}" -n blackbox rollout status statefulset/clickhouse --timeout 5m; then
  "${kubectl[@]}" -n blackbox get pvc data-clickhouse-0 >&2 || true
  "${kubectl[@]}" -n blackbox events --for pod/clickhouse-0 >&2 || true
  exit 1
fi

# Waits for the Job to finish either way, so a failure shows the SQL error at once.
job_finished() {
  local state
  for _ in {1..60}; do
    state=$("${kubectl[@]}" -n blackbox get job clickhouse-schema \
      -o jsonpath='{.status.conditions[?(@.status=="True")].type}')
    case $state in
      *Complete*) return 0 ;;
      *Failed*) return 1 ;;
    esac
    sleep 5
  done
  echo "job/clickhouse-schema didn't finish in 5 minutes" >&2
  return 1
}

"${kubectl[@]}" -n blackbox create configmap clickhouse-schema \
  --from-file=deploy/clickhouse/schema.sql --dry-run=client -o yaml |
  "${kubectl[@]}" apply -f - >/dev/null
"${kubectl[@]}" -n blackbox delete job clickhouse-schema --ignore-not-found >/dev/null
"${kubectl[@]}" apply -f deploy/clickhouse/schema.yaml >/dev/null
if ! job_finished; then
  "${kubectl[@]}" -n blackbox logs --prefix --tail 20 \
    -l batch.kubernetes.io/job-name=clickhouse-schema >&2 || true
  exit 1
fi
"${kubectl[@]}" -n blackbox logs job/clickhouse-schema

# shellcheck disable=SC2016 # expanded in the Pod, where the password lives
"${kubectl[@]}" -n blackbox exec clickhouse-0 -- bash -c 'clickhouse-client --password "$CLICKHOUSE_PASSWORD" \
  --query "SELECT version() AS version, formatReadableSize(free_space) AS free, formatReadableSize(keep_free_space) AS kept FROM system.disks FORMAT PrettyCompact"'
