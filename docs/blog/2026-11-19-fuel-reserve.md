# Fuel reserve: ClickHouse beside Redpanda

*19 November 2026*

## What was done

Tonight ClickHouse joined Redpanda on data-1, for
[#15](https://github.com/guy-with-a-why/telemetry-blackbox/issues/15). One
server runs as a StatefulSet on a second local volume, and a Job applies the
schema on every deploy. Frames land in three tables. `frames_raw` keeps every
delivery, duplicates included, for seven days. `frames` keeps one row per
frame for thirty, and `frames_per_second` rolls them up for ninety.

`just clickhouse` deploys the lot in about 11 seconds once the image is on the
node, and a second run changes nothing. `just clickhouse-check` covers the
issue's other box. It inserts 10,000 frames twice, the way Spate redelivers a
batch after a crash, then counts. `frames` held 20,000 rows in two parts
before a merge, 10,000 with `FINAL` and 10,000 in one part after the merge.
The rollup counted 10,000. The server landed in
[#141](https://github.com/guy-with-a-why/telemetry-blackbox/pull/141), and the
tables and the check in
[#142](https://github.com/guy-with-a-why/telemetry-blackbox/pull/142).

## Why was it done that way

The disk came first. data-1 has one 38 GiB filesystem, and both Redpanda and
ClickHouse live on it. Redpanda
[refuses writes](https://docs.redpanda.com/current/manage/cluster-maintenance/disk-utilization/)
when free space falls under 5 GiB, and its retention lets it burn about 7 GiB
more. The kubelet draws its line higher. Containerd shares the disk, so the
kubelet starts
[evicting](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)
at 15% free, about 5.7 GiB, and that's the real reserve. ClickHouse stops
taking inserts while less than 14 GiB is free. That's the reserve plus
everything Redpanda might still use and a little spare, so ClickHouse can never
be the one that runs data-1 dry. The order they stop in matters. If ClickHouse stops, Spate stops committing and the
frames wait in Redpanda. If Redpanda stopped, the gateway would have nowhere to
put them. A two-hour flight at 250 frames a second takes 50 MiB per table, so a
month of evenings fits in about 2 GiB of the almost 10 ClickHouse is left with.

Then the key. The issue said the deduplicated table was keyed on
`(boot_id, system_id, seq)`, and so did the README. MAVLink's `seq` is one byte
and wraps at 255, so that key would treat frame 1 and frame 257 as the same
frame and quietly delete real data. The key has to be unique per frame and
identical on every redelivery, and I weighed two ways to get one.

The first was to have the gateway unwrap `seq` into a 64-bit counter. It reads
the stream in order, so counting wraps looks easy. It breaks in two places. A
gateway restart resets the count, unless the gateway keeps state on disk. And
the 60-second serial cut in Leg 4 drops thousands of frames, so when the link
comes back the gateway can't tell how many times `seq` wrapped while it was
gone. The key would be wrong in exactly the drill meant to prove nothing was
lost.

The second, and the one I took, was Redpanda's partition and offset. Redpanda
gives each record one offset when it's written, and Spate redelivers a batch
from those same offsets, so a duplicate carries the first copy's key exactly.
Nothing has to be counted or remembered. It does rely on the gateway writing
each frame once, and the
[idempotent producer](https://docs.redpanda.com/current/develop/produce-data/idempotent-producers/)
planned in
[#19](https://github.com/guy-with-a-why/telemetry-blackbox/issues/19) covers
that, because the broker recognises a retried send and keeps one copy. `seq`
stays in the table for what it's good at, which is spotting gaps between
neighbours. ADR 4 in
[#24](https://github.com/guy-with-a-why/telemetry-blackbox/issues/24) will
record the decision.

The rollups needed the same care. A plain materialised view runs on each
insert, before any merge has removed a duplicate, so it would count a
redelivered batch twice. The rollup is a
[refreshable view](https://clickhouse.com/docs/materialized-view/refreshable-materialized-view)
instead. Every 10 seconds it finds the seconds that gained a row since its last
refresh and recounts them from `frames_raw`, grouping by offset so each frame
counts once, at its first arrival. Its own latest refresh is the watermark, so
a stopped server catches up on the next run. With a two-hour flight already
stored, a refresh on data-1 takes 42 to 46 ms and reads about 51,000 rows:
22,500 new frames, and the rollup itself to find its watermark. That second
part grows with the rollup's history, so it's the first thing to tune once the
firmware's real frame rates arrive.

ClickHouse also logs itself into system tables that nothing deletes, and
`text_log` records every trace line. I keep three of them for three days and
drop the rest. Its mark cache defaults to 5 GiB, more memory than data-1 has,
so it gets 256 MiB.

## What challenges were faced

ClickHouse 26.8 crashed with `Illegal instruction` before it logged a line.
From 26.6 the amd64 image
[needs x86-64-v3](https://hub.docker.com/r/clickhouse/clickhouse-server),
which means AVX2, and my home server runs a 2012 i5 that stops at AVX. The VMs
already see the host's CPU as it is, so there was nothing more to expose. I
pinned 26.3, the last LTS before the change, which is supported until March
2027. Real hardware would take 26.8. The broken image spent almost five minutes
coming down my connection before it got the chance to fail.

Even with the right image, the StatefulSet stayed on the broken Pod. With
ordered rolling updates, a StatefulSet won't replace a Pod that never became
Ready, and Kubernetes documents the way out as a
[forced rollback](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#forced-rollback).
Deleting the Pod let 26.3 through, and the README now says so beside the
deploy.

The last one was in my own script. ClickHouse's config is mounted by
`subPath`, which the kubelet never refreshes, so a changed config needs a
restart. My first version restarted when `kubectl apply` reported the ConfigMap
changed and the StatefulSet unchanged. It never fired, because apply reports a
StatefulSet with claim templates as changed on every run. The script now puts a
hash of the ConfigMap on the Pod template, so a change rolls the Pod in about
15 seconds and a rerun leaves it alone.

A second pass over both PRs left eight comments, each fixed in a commit that
answers it, and two of them changed the design. My first floor was 12 GiB,
sized against Redpanda's 5 GiB and blind to the kubelet's 15%. And the rollup
only looked back five minutes, so frames from a refresh missed for longer than
that, say the VMs stopping straight after a flight, would never have been
counted. The floor is now worked out from the kubelet's line, and the deploy's
README shows the sum. The rollup has no window left to outlast. The check
passed on data-1 with all eight fixes in.

## What's next

Leg 1 lands tomorrow. The checkpoint in
[#17](https://github.com/guy-with-a-why/telemetry-blackbox/issues/17) is left,
on quorum, static Pods and MergeTree merges, then the leg's debrief. The
biggest risk on data-1 is now memory rather than disk. Redpanda and ClickHouse
claim 2.5 GiB of its 4 between them, before the pipeline and Grafana arrive in
Leg 3. The fallback is to give data-1 another gigabyte from the host's
headroom.

## Quiz

Five questions on the post. Open one for my answer.

<details>
<summary>Why can't <code>seq</code> be the key that removes
duplicates?</summary>

It's one byte and wraps at 255, so frame 1 and frame 257 share a key and one of
them would be deleted. It still counts gaps between neighbouring frames.

</details>

<details>
<summary>Why is deduplication in a ReplacingMergeTree eventual?</summary>

A part is never changed once written, so an insert doesn't look for an earlier
copy. The duplicate goes when a background
[merge](https://clickhouse.com/docs/merges) puts both copies in one part, and
ClickHouse decides when that happens.

</details>

<details>
<summary>What does <code>FINAL</code> do, and why not use it
everywhere?</summary>

It does the merge's deduplication at query time, so the answer is right before
the merge runs. It costs work on every query, so it's for reads that must be
exact, such as bbcheck's.

</details>

<details>
<summary>Why does ClickHouse stop at 14 GiB free and not at 5?</summary>

5 GiB is Redpanda's floor, but the kubelet starts evicting at 15% free, about
5.7 GiB. Redpanda can still grow by about 7 GiB, so stopping at 14 keeps data-1
clear of both, and frames wait in Redpanda instead of being lost at the
gateway.

</details>

<details>
<summary>Why a refreshable view for the rollups, not a plain materialised
view?</summary>

A plain view runs on each insert, before any merge, so it counts a redelivered
batch twice. The refreshable one recounts recent seconds from `frames_raw`,
grouping by offset, so each frame counts once.

</details>
