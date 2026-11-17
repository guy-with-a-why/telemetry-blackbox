#!/usr/bin/env bash
# Watches the cluster through a drill. It deploys the echo workload in
# deploy/drills/, then probes every second or so (a round waits up to 3 s for
# its probes) and prints a line whenever the answer changes:
#   up     the control planes Multipass reports running
#   vip    the control plane that holds the VIP, as Multipass lists it, so it
#          still answers when the API doesn't
#   echo   the echo Service, through the first worker's NodePort
#   read   a consistent read through the VIP, which etcd serves only with quorum
#   cache  the same read at resourceVersion=0, which the API server's watch
#          cache serves without asking etcd
#   write  a patch to the drill's ConfigMap through the VIP
# Ctrl-C stops it and prints how many probes of each kind passed. It never
# runs multipass exec, because that starts a stopped VM and would undo the
# drill.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

kubeconfig=$HOME/.kube/blackbox.conf
if [[ ! -f $kubeconfig ]]; then
  echo "no $kubeconfig; run just cluster-up" >&2
  exit 1
fi
# An array, not a function, because timeout can only run a program.
kubectl=(kubectl --kubeconfig "$kubeconfig")

"${kubectl[@]}" apply -f deploy/drills/echo.yaml >/dev/null
"${kubectl[@]}" -n drill rollout status deployment/echo --timeout 2m >/dev/null

# Column 3 is the address each VM leased.
worker_ip=$(multipass list --format csv | awk -F, -v name="${workers[0]}" '$1 == name { print $3 }')
if [[ -z $worker_ip ]]; then
  echo "${workers[0]} has no address; is it running?" >&2
  exit 1
fi
config=/api/v1/namespaces/drill/configmaps/drill-watch
echo "echo is ready on ${workers[0]} ($worker_ip:30080). Start the drill; Ctrl-C stops."

# Each probe prints ok or fail, and none takes longer than 3 s.
probe() { if timeout 3 "$@" >/dev/null 2>&1; then echo ok; else echo fail; fi; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

declare -A passed=()
kinds=(echo read cache write)
ticks=0
summary() {
  echo
  for kind in "${kinds[@]}"; do
    echo "$kind: ${passed[$kind]:-0} of $ticks passed"
  done
  exit 0
}
trap summary INT TERM

start=$SECONDS
last=
while true; do
  # AllIPv4 (column 5) is quoted and comma-joined, so with the quotes gone every
  # address the VM has, the VIP included, is a field from 5 onwards.
  read -r up holder < <(multipass list --format csv | tr -d '"' | awk -F, -v vip="$vip" '
    $1 ~ /^cp-/ && $2 == "Running" {
      up = up (up ? "," : "") $1
      for (i = 5; i <= NF; i++) if ($i == vip) holder = $1
    }
    END { print (up ? up : "none"), (holder ? holder : "none") }')

  # Run the probes side by side, so one that times out doesn't stall the rest.
  probe curl -fsS "http://$worker_ip:30080/hostname" >"$tmp/echo" &
  probe "${kubectl[@]}" get --raw "$config" >"$tmp/read" &
  probe "${kubectl[@]}" get --raw "$config?resourceVersion=0" >"$tmp/cache" &
  probe "${kubectl[@]}" -n drill patch configmap drill-watch --type merge \
    -p "{\"data\":{\"tick\":\"$ticks\"}}" >"$tmp/write" &
  wait

  ((++ticks))
  line="up $up  vip $holder"
  for kind in "${kinds[@]}"; do
    result=$(<"$tmp/$kind")
    line+="  $kind $result"
    if [[ $result == ok ]]; then ((++passed[$kind])); fi
  done
  if [[ $line != "$last" ]]; then
    printf '%s  +%4ss  %s\n' "$(date +%T)" "$((SECONDS - start))" "$line"
    last=$line
  fi
  sleep 1
done
