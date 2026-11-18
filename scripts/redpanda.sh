#!/usr/bin/env bash
# Runs on the server. Deploys Redpanda on data-1's own disk: the StorageClass
# and the volume, the volume's directory on the node, then the broker and its
# topics. Safe to run again. Each wait that fails says why, rather than ending
# on a bare timeout.
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
pv() { "${kubectl[@]}" get pv redpanda -o jsonpath="{$1}"; }

# A volume's path, node and claim template can't change once created. If
# apply refuses one, delete the object and run this again.
"${kubectl[@]}" apply -f deploy/namespace.yaml -f deploy/storage/local.yaml \
  -f deploy/redpanda/volume.yaml >/dev/null

# With Retain, deleting the claim leaves the volume Released and still holding
# the old claim's UID, so a new claim never binds. Stop here, not at a timeout.
if [[ $(pv .status.phase) == Released ]]; then
  echo "pv/redpanda is Released and won't bind again; free it, then run this again:" >&2
  echo "  kubectl patch pv redpanda --type json -p '[{\"op\": \"remove\", \"path\": \"/spec/claimRef/uid\"}]'" >&2
  exit 1
fi

# A local volume mounts a directory that must already exist. The volume says
# where, so the path and the node live in one place. Redpanda runs as uid 101.
path=$(pv .spec.local.path)
node=$(pv '.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[?(@.key=="kubernetes.io/hostname")].values[0]')
if [[ -z $path || " ${node_names[*]} " != *" $node "* ]]; then
  echo "pv/redpanda needs a local path and a hostname affinity on one of: ${node_names[*]}" >&2
  exit 1
fi
# multipass exec starts the VM if it's stopped, which a deploy wants.
multipass exec "$node" -- sudo install -d -o 101 -g 101 -m 0750 "$path"

"${kubectl[@]}" apply -f deploy/redpanda/redpanda.yaml >/dev/null
if ! "${kubectl[@]}" -n blackbox rollout status statefulset/redpanda --timeout 5m; then
  # Usually the claim: unbound, or bound to a node that's down.
  "${kubectl[@]}" -n blackbox get pvc data-redpanda-0 >&2 || true
  "${kubectl[@]}" -n blackbox events --for pod/redpanda-0 >&2 || true
  exit 1
fi

# Waits for the Job to finish either way, so a failure shows rpk's error at once.
job_finished() {
  local state
  for _ in {1..60}; do
    state=$("${kubectl[@]}" -n blackbox get job redpanda-topics \
      -o jsonpath='{.status.conditions[?(@.status=="True")].type}')
    case $state in
      *Complete*) return 0 ;;
      *Failed*) return 1 ;;
    esac
    sleep 5
  done
  echo "job/redpanda-topics didn't finish in 5 minutes" >&2
  return 1
}

"${kubectl[@]}" -n blackbox delete job redpanda-topics --ignore-not-found >/dev/null
"${kubectl[@]}" apply -f deploy/redpanda/topics.yaml >/dev/null
if ! job_finished; then
  "${kubectl[@]}" -n blackbox logs --prefix --tail 20 \
    -l batch.kubernetes.io/job-name=redpanda-topics >&2 || true
  exit 1
fi
"${kubectl[@]}" -n blackbox exec redpanda-0 -- rpk topic list
