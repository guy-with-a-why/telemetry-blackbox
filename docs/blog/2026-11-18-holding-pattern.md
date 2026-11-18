# Holding pattern: Redpanda on data-1's own disk

*18 November 2026*

## What was done

Tonight Redpanda went onto the cluster, for
[#14](https://github.com/guy-with-a-why/telemetry-blackbox/issues/14). It's
where every frame will circle until ClickHouse is ready to take it, so it has to
hold them through anything short of losing the disk. One broker runs as a
[StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) in dev mode, on a 10 Gi volume on data-1, with a `telemetry.raw`
topic of six partitions.

`just redpanda` deploys it and is safe to run again. A second run takes 15
seconds and changes nothing. `just redpanda-check` proves the issue's first
box. It writes 10,000 numbered records, deletes the Pod and reads every one
back once the StatefulSet has replaced it. The broker was back on data-1 in 7
seconds with none missing, and 100,000 records came back the same way.

Redpanda's image lives on Docker Hub, so the host gained a fourth pull-through
mirror first, in
[#125](https://github.com/guy-with-a-why/telemetry-blackbox/pull/125). The
broker and the check landed in
[#127](https://github.com/guy-with-a-why/telemetry-blackbox/pull/127) and
[#128](https://github.com/guy-with-a-why/telemetry-blackbox/pull/128).

## Why was it done that way

The cluster had no StorageClass, so a claim had nowhere to go. A
[StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/) is the menu an admin offers: who creates a volume, when a claim binds to it and
what happens to the data afterwards. Mine is called `local` and has no
provisioner. I create each volume by hand, as a
[local volume](https://kubernetes.io/docs/concepts/storage/volumes/#local) on one node's disk, pinned to that
node. [Binding waits](https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode) for the
first Pod that uses the claim, so the scheduler picks a node before the claim
picks a volume. With immediate binding,
a claim could take a volume on a node the Pod can't run on. The volume is set to
[Retain](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#retain), so deleting the claim never
deletes frames.

I passed over replicated storage such as Longhorn. There's one data node, so it
has nowhere to copy to, and with more nodes Redpanda and ClickHouse would
replicate their own data more cheaply than a disk layer could. The price of
local disks is that a stateful Pod can't move. Draining data-1 stops Redpanda
until the node is back, and the drain drill in
[#27](https://github.com/guy-with-a-why/telemetry-blackbox/issues/27) will show
it. A dynamic provisioner is in Stretch as
[#124](https://github.com/guy-with-a-why/telemetry-blackbox/issues/124), for
everything that doesn't need a hand-made volume.

Redpanda is built on [Seastar](https://seastar.io/), the same framework as
ScyllaDB. It runs one
thread per core, claims its memory at startup and writes past the page cache.
So `--smp=1 --memory=512M` gives it one core and 512 MB, and `--overprovisioned`
stops it pinning and busy-polling data-1's two shared vCPUs. The container's
limit is 1 GiB, because Seastar's share doesn't cover the binary or its thread
stacks.

The bash behind the cluster is now about 610 lines. Talos, OpenTofu and Flux
would bring that to one 60-line script plus about 350 lines of configuration,
and I've filed that rebuild as
[#130](https://github.com/guy-with-a-why/telemetry-blackbox/issues/130) with
six sub-issues. I'm not starting it yet. Building kubeadm by hand is the point
of this leg, and the bash works, is linted and is about to stop changing, so
replacing it now would be a rewrite rather than paying off debt. The Leg 4
drills are the safety net that will prove a new platform moved nothing, and
Flux in
[#107](https://github.com/guy-with-a-why/telemetry-blackbox/issues/107) should
come first, so the workloads are declarative before the layer underneath them
changes. Writing it down now, with a trigger, makes it planned work. It also
retired an issue that would have polished scripts #130 replaces.

## What challenges were faced

The first deploy timed out. I'd rebuilt the cluster from a checkout on my home
server that predated the mirror, so nothing on the bridge served Docker Hub.
Redpanda's 122 MB image came straight down my connection at about 2 minutes a
node, which outlasted the script's 2-minute wait for the topic Job. The broker
and the Job had both finished fine. The wait is now 5 minutes, matching the
rollout. `just vms-check` would have caught the missing mirror, and `just up`
doesn't run it yet.

The real mistake was durability.
[Dev mode](https://docs.redpanda.com/current/reference/rpk/rpk-redpanda/rpk-redpanda-mode/) turns write
caching on, which acknowledges a write before it reaches the disk, so my first
version turned it off with a
[bootstrap file](https://docs.redpanda.com/current/manage/cluster-maintenance/cluster-property-configuration/)
and called the broker durable. A second pass over the
manifests found that dev mode also starts the broker with
`--unsafe-bypass-fsync=true`, so an ack no longer waited for the disk to
confirm the write. Deleting a Pod leaves every cache below it intact, so the
restart check passed 100,000 records, which proves the caches are very reliable
right up until the power goes. The broker now starts with
`--unsafe-bypass-fsync=false`, and its command line in the logs shows it. A restart check can't see this class of fault. The Leg 4
drills should include stopping data-1 hard.

I also broke the deploy on purpose to see how it fails. A volume left
`Released` after its claim was deleted now stops the script at once and prints
the command that frees it, rather than ending on a 5-minute timeout. A topic Job
that can't reach the broker prints rpk's own error within 25 seconds. That
needed `restartPolicy: Never`, because with `OnFailure` the Job deletes its Pod
when it
[gives up](https://kubernetes.io/docs/concepts/workloads/controllers/job/#handling-pod-and-container-failures)
and the logs go with it.

## What's next

ClickHouse is next, on the same `local` class, in
[#15](https://github.com/guy-with-a-why/telemetry-blackbox/issues/15). The risk
is data-1's 40 GB disk. Redpanda
[refuses writes](https://docs.redpanda.com/current/manage/cluster-maintenance/disk-utilization/) when free
space falls under 5 GiB, and it measures that against the whole filesystem ClickHouse will share.
ClickHouse's retention is the first lever, and a bigger disk for data-1 is the
fallback. Leg 1 lands on Friday, with the decisions in
[#16](https://github.com/guy-with-a-why/telemetry-blackbox/issues/16) and its
debrief.

## Quiz

Five questions on the post. Open one for my answer.

<details>
<summary>Why does <code>telemetry.raw</code> have six partitions, and what does
a key decide?</summary>

A partition is an ordered log, and it's the unit consumers
[share out](https://docs.redpanda.com/current/get-started/architecture/). Six let up
to six consumers in one group read in parallel. The key's hash picks the
partition, so every frame with the same key stays in order.

</details>

<details>
<summary>What's an offset, and who keeps it for a consumer group?</summary>

An offset is a record's position in its partition. The group
[commits the offset](https://docs.redpanda.com/current/develop/consume-data/consumer-offsets/) it has
processed to the broker, so a restarted consumer carries on from there.
Committing only after ClickHouse confirms a batch is what makes delivery
at-least-once.

</details>

<details>
<summary>Why does the <code>local</code> class wait for the first consumer
before binding?</summary>

A local volume only exists on one node. Waiting lets the scheduler place the Pod
first, so the claim binds to a volume the Pod can actually reach.

</details>

<details>
<summary>The claim was deleted and recreated. Why won't the volume bind
again?</summary>

With Retain, the volume goes `Released` and keeps the old claim's UID. Removing
that UID makes it `Available` for the new claim, and the data is still there.

</details>

<details>
<summary>Write caching was off. Why could Redpanda still lose acknowledged
frames?</summary>

Dev mode also skipped fsync, so an ack didn't wait for the disk to confirm the
write. A Pod restart keeps whatever is still cached, and a power cut doesn't.

</details>
