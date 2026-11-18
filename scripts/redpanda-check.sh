#!/usr/bin/env bash
# Usage: redpanda-check.sh [records]
# Checks the broker keeps its data across a Pod restart. It writes numbered
# records to a scratch topic, deletes the Pod, waits for the StatefulSet to
# bring it back, then reads every record back. The scratch topic keeps test
# records out of telemetry.raw, and it's deleted at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

records=${1:-10000}
topic=blackbox.check
kubeconfig=$HOME/.kube/blackbox.conf
if [[ ! -f $kubeconfig ]]; then
  echo "no $kubeconfig; run just cluster-up" >&2
  exit 1
fi
kubectl=(kubectl --kubeconfig "$kubeconfig" -n blackbox)
rpk() { "${kubectl[@]}" exec -i redpanda-0 -- rpk "$@"; }
pod() { "${kubectl[@]}" get pod redpanda-0 -o jsonpath="{$1}" 2>/dev/null; }
# The records the broker holds: the sum of every partition's high watermark.
held() { rpk topic describe "$topic" -p | awk 'NR > 1 { sum += $6 } END { print sum + 0 }'; }

rpk topic create "$topic" -p 6 -r 1 >/dev/null
trap 'rpk topic delete "$topic" >/dev/null 2>&1 || true' EXIT

# Each record is keyed by its number, so they spread over all six partitions.
# With acks=all, rpk returns only once the broker has written every one.
seq 1 "$records" | awk '{ print $1, $1 }' |
  rpk topic produce "$topic" -f '%k %v\n' --acks=-1 >/dev/null
before=$(held)
echo "wrote $before of $records records to $topic"

# The new Pod has the same name, so wait for a new UID, not just a Ready Pod.
uid=$(pod .metadata.uid)
start=$SECONDS
"${kubectl[@]}" delete pod redpanda-0 --wait >/dev/null
until new=$(pod .metadata.uid) && [[ -n $new && $new != "$uid" ]]; do sleep 1; done
"${kubectl[@]}" wait pod/redpanda-0 --for condition=Ready --timeout 3m >/dev/null
echo "restarted redpanda-0 on $(pod .spec.nodeName) in $((SECONDS - start)) s"

after=$(held)
read_back=""
if ((after > 0)); then
  read_back=$(rpk topic consume "$topic" -o start -n "$after" -f '%v\n')
fi
missing=$(comm -23 <(seq 1 "$records" | sort) <(sort -u <<<"$read_back") | wc -l)
duplicates=$(($(grep -c . <<<"$read_back" || true) - $(sort -u <<<"$read_back" | grep -c . || true)))
echo "read back $after records: $missing missing, $duplicates duplicates"
((before == records && missing == 0))
