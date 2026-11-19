#!/usr/bin/env bash
# Usage: clickhouse-check.sh [frames]
# Shows that deduplication is eventual. It applies schema.sql to a scratch
# database, inserts one batch of frames twice, as Spate does when it crashes
# between the insert and the commit, then counts what each table holds before
# and after a merge. The scratch database keeps test rows out of blackbox, and
# it's dropped at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

frames=${1:-10000}
db=blackbox_check
kubeconfig=$HOME/.kube/blackbox.conf
if [[ ! -f $kubeconfig ]]; then
  echo "no $kubeconfig; run just cluster-up" >&2
  exit 1
fi
kubectl=(kubectl --kubeconfig "$kubeconfig" -n blackbox)
# shellcheck disable=SC2016 # expanded in the Pod, where the password lives
client=(bash -c 'clickhouse-client --password "$CLICKHOUSE_PASSWORD" "$@"' client)
ch() { "${kubectl[@]}" exec clickhouse-0 -- "${client[@]}" --database "$db" --query "$1"; }

# A run that was killed leaves its database behind, with its rows and maybe
# an older schema, so each run starts from an empty one.
"${kubectl[@]}" exec clickhouse-0 -- "${client[@]}" --query "DROP DATABASE IF EXISTS $db SYNC"
"${kubectl[@]}" exec clickhouse-0 -- "${client[@]}" --query "CREATE DATABASE $db"
trap 'ch "DROP DATABASE IF EXISTS $db SYNC" >/dev/null 2>&1 || true' EXIT
"${kubectl[@]}" exec -i clickhouse-0 -- "${client[@]}" --database "$db" --multiquery \
  <deploy/clickhouse/schema.sql

# Merges run in the background whenever ClickHouse likes. Stopping them
# shows the table as it is between the redelivery and the merge.
ch "SYSTEM STOP MERGES frames"

# One boot's frames at 250 a second, from the start of today in UTC. They
# all land in one day's partition, so the part counts below mean one thing
# even when the check runs near midnight. Both inserts are the same records,
# so they carry the same offsets and receive times.
boot=$(cat /proc/sys/kernel/random/uuid)
insert="INSERT INTO frames_raw (boot_id, system_id, component_id, seq, msg_id, partition, offset, received_at, payload)
  SELECT '$boot', 1, 1, number % 256, 30, 0, number, toDateTime64(toStartOfDay(now(), 'UTC'), 6, 'UTC') + number / 250, 'frame'
  FROM numbers($frames)"
ch "$insert"
ch "$insert"

raw=$(ch "SELECT count() FROM frames_raw")
before=$(ch "SELECT count() FROM frames")
parts=$(ch "SELECT count() FROM system.parts WHERE active AND database = '$db' AND table = 'frames'")
final=$(ch "SELECT count() FROM frames FINAL")
echo "inserted $frames frames twice"
echo "frames_raw holds $raw rows, one for each delivery"
echo "frames holds $before rows in $parts parts before a merge, and $final with FINAL"

ch "SYSTEM START MERGES frames"
ch "OPTIMIZE TABLE frames FINAL"
after=$(ch "SELECT count() FROM frames")
parts=$(ch "SELECT count() FROM system.parts WHERE active AND database = '$db' AND table = 'frames'")
echo "frames holds $after rows in $parts part after a merge"

# The rollup refreshes every 10 seconds. This runs it now and waits for it.
ch "SYSTEM REFRESH VIEW frames_per_second_mv"
ch "SYSTEM WAIT VIEW frames_per_second_mv"
read -r rolled seconds < <(ch "SELECT sum(frames), count() FROM frames_per_second FINAL")
echo "frames_per_second counts $rolled frames over $seconds seconds"

failed=()
((raw == 2 * frames)) || failed+=("frames_raw holds $raw rows, not $((2 * frames))")
((before == 2 * frames)) || failed+=("frames held $before rows before the merge, not $((2 * frames))")
((final == frames)) || failed+=("FINAL gave $final rows, not $frames")
((after == frames)) || failed+=("frames holds $after rows after the merge, not $frames")
((rolled == frames)) || failed+=("frames_per_second counts $rolled frames, not $frames")
if ((${#failed[@]})); then
  printf 'FAIL: %s\n' "${failed[@]}" >&2
  exit 1
fi
