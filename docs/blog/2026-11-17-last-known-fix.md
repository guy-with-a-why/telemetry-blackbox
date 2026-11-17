# Last known fix: etcd restored from a snapshot

*17 November 2026*

## What was done

Tonight I took a snapshot of etcd, deleted a namespace and brought it back, for
[#13](https://github.com/guy-with-a-why/telemetry-blackbox/issues/13).
Restoring a snapshot puts the whole cluster back at its last known fix, the
moment the snapshot was taken, and anything that happened after it is gone.

`just etcd-snapshot` takes one from the first running control plane, copies it
to my home server and checks the copy's hash. It takes 9 seconds and comes to
15 MB.

![From my laptop, ssh server runs the snapshot script. It saves a snapshot from cp-1 and prints its sha256 and a table: hash 7a4b125, revision 2000386077, 502 keys, 15 MB, storage version 3.6.0. It was taken after both restores, so the revision carries two jumps of a billion.](assets/2026-11-17-etcd-snapshot.gif)

I ran the drill twice. The first time I worked each step out as I went, from
the kubeconfig to the restore flags, and reads failed for 19 minutes. I wrote
the runbook from that run and followed it for the second run. Reads were back
93 seconds after the API servers stopped, and echo answered a minute later. The
namespace came back with its old UID and creation time, so as far as Kubernetes
knows, it never left.

![kubectl on my laptop shows the drill namespace, deleted at 20:38 and restored at 20:40, with UID 5144704d and a creation time of 20:09:40, from before the delete. Both echo Pods are Running at 47 minutes old, on 10.244.3.252 on edge-1 and 10.244.5.199 on data-1. The drill ConfigMap's resourceVersion is 2000383099, two jumps of a billion on.](assets/2026-11-17-same-namespace.gif)

The [runbook](../runbooks/etcd.md) has the steps and the output.

## Why was it done that way

[Velero](https://velero.io/docs/) is the obvious alternative. It backs up
objects through the API and can restore one namespace on its own, which is all
this drill asks for. It can't help when the control plane itself is lost, and
that's the failure an etcd snapshot covers. The snapshot is the floor, so it
comes first. Object backups can sit on top of it later.

etcd runs as three members, one on each control plane, and the workers run
none. A member is a single etcd server with its own data, ID and peer address.
The snapshot goes through `crictl` inside the etcd container, because I'll need
a snapshot most when the API is down. It reads one member's own database, so it
doesn't need quorum either. The file holds every Secret in plain text, so it's
readable only by me.

Every member restores from the same file. One member restored alone would get a
new cluster ID from the restore, and the other two would reject it. So every API
server and etcd member stops, all three restore with one member list and they
start as a new cluster that agrees from the first heartbeat. Each node keeps its
old data directory until the cluster checks clean. If a member won't start, all
three go back to it, never one or two. The
[etcd recovery guide](https://etcd.io/docs/v3.6/op-guide/recovery/) covers the
mechanics.

The restore also moves the revision a billion ahead and marks everything older
as compacted. The kubelets and controllers watch from the last revision they
saw, which is newer than the snapshot. Without the jump, new writes would reuse
numbers the watchers had already passed, so they'd never see them. With it,
every watcher gets 410 Gone and lists everything again. The Kubernetes docs also
restart the scheduler, the controller manager and the kubelets after a restore.
I don't, because the relist covers it, and the second run showed that's enough
here.

## What challenges were faced

Before I could start, Multipass was down. Overnight, snapd refreshed it from
1.17.1 down to 1.17.0 and suspended all five VMs on the way. Their saved state
pointed at the newer version's firmware, so the older one crashed trying to
resume them and left its DNS server holding port 53. Every restart after that failed on the port, which hid
the real cause. Reverting to 1.17.1 brought all five back, and etcd recovered
without a hand on it. Multipass now refreshes when I say so.

My first copy to a control plane went through `multipass exec`, and only 2.2 MB
of the 15 arrived. `etcdutl` refused it, because every snapshot ends with a hash
of its contents, so a torn copy fails safely. The runbook now copies with
`multipass transfer` and checks the hash on every node before anything stops.

kubeadm left a trap too. It grew the cluster one join at a time, so cp-1's etcd
manifest lists only cp-1 as the initial cluster. Copy that into a restore and
cp-1 starts a cluster of its own. The runbook spells out all three members.

## What's next

Redpanda on local storage is next, in
[#14](https://github.com/guy-with-a-why/telemetry-blackbox/issues/14), then
ClickHouse in
[#15](https://github.com/guy-with-a-why/telemetry-blackbox/issues/15). The risk
is data-1's 4 GB holding both. Their memory limits are the first lever, and
giving data-1 6 GB is the fallback, since the home server has the room. Leg 1
is due on Friday.

## Quiz

Five questions on the post. Open one for my answer.

<details>
<summary>Why can't an etcd restore bring back one namespace on its own?</summary>

A snapshot is the whole database at one revision. Restoring it puts every
object back to that moment, and everything written since is lost.

</details>

<details>
<summary>Why restore every member, rather than one and let the others catch
up?</summary>

The restore gives that member a new cluster ID. The other two still have the
old one, so they reject it.

</details>

<details>
<summary>What does <code>--bump-revision</code> protect against?</summary>

Watchers that saw revisions newer than the snapshot. The jump stops new writes
reusing those numbers, and `--mark-compacted` makes the watchers get 410 Gone
and relist.

</details>

<details>
<summary>Why take the snapshot through <code>crictl</code> and not the
API?</summary>

The API is the thing most likely to be gone when I need a snapshot. `crictl`
only needs the node and a running etcd container.

</details>

<details>
<summary>echo's Pods came back with their old names but new addresses.
Why?</summary>

The restore brought back the Pod objects, still bound to their nodes. The
kubelets had torn down their sandboxes when the namespace went, so they built
new ones, and Cilium gave each a new address.

</details>
