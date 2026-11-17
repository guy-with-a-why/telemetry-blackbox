# Deadstick: two control planes down

*16 November 2026*

## What was done

Tonight I took the control planes down on purpose, one and then two, for
[#12](https://github.com/guy-with-a-why/telemetry-blackbox/issues/12). Losing
cp-2 changed nothing: etcd kept a
[majority](https://etcd.io/docs/v3.5/faq/#what-is-failure-tolerance), two of
three. cp-1 held the virtual IP all along, so this run never made kube-vip
move it. Timing that move means stopping whichever control plane holds it.

Losing cp-3 as well took the majority with it. Writes stopped on the next probe.
The API server kept answering
[cached reads](https://kubernetes.io/docs/reference/using-api/api-concepts/#semantics-for-get-and-list)
for another 22 seconds, until kube-vip couldn't renew its
[Lease](https://kubernetes.io/docs/concepts/architecture/leases/) and gave up
the address. [Yesterday's post](2026-11-15-engine-start.md#whats-next)
predicted that.

The echo Pods on the workers didn't notice, and answered 79 of 79 probes. It's a
deadstick glide: nothing gets rescheduled or replaced, but everything already
flying carries on, because running Pods and
[kube-proxy's iptables rules](https://kubernetes.io/docs/reference/networking/virtual-ips/)
don't need the control plane. Starting cp-2 and cp-3 brought quorum back, and
`cluster-check` passed once Cilium settled. The
[runbook](../runbooks/control-plane.md) has the output.

## Why was it done that way

The drill needed a witness that doesn't lean on what it's watching.
`just drill-watch` runs on the home server, outside the cluster, and logs every
change in echo, the API and the address. It sends a consistent read, which needs
quorum, and a cached read at `resourceVersion=0`, which doesn't, so I can tell
an API server that has lost etcd from one that has gone. Each VM goes down with
`multipass stop --force`, which pulls the power, because a clean shutdown lets
etcd hand over leadership first and real failures don't.
[#111](https://github.com/guy-with-a-why/telemetry-blackbox/pull/111) has the
script.

An infrastructure engineer I know asked me why all this runs on Bash instead of
Terraform. Terraform reconciles a state file against an API, and its Multipass
provider documents no zone option, which kube-vip needs. The drills break VMs
by hand too, so the state would be wrong after every drill. The scripts check
what's there before they act, so the cluster is its own record. Terraform also
stops at the machines, and the hard part is ten kubeadm commands in order
across five of them. On real machines, or a hypervisor with an API such as
Proxmox, Terraform for the machines and Ansible for kubeadm would earn their
place, as [ADR 6](../adr/0006-scripted-kubeadm-bootstrap.md) says.

## What challenges were faced

The first run ended early, for a reason that had nothing to do with etcd. With
cp-2 and cp-3 down, I ran `just cluster-check`, and afterwards all five VMs were
running. I hadn't started any of them. Multipass's log had cp-2 booting at
19:54:00 and cp-3 twenty seconds later. `cluster-check` finds a ready API server
by running `multipass exec` on each control plane in turn. Without quorum cp-1
wasn't ready, so it moved on to the stopped ones, and `multipass exec` starts a
stopped VM first. Its help doesn't say so. Its source does. The tool meant to
report the outage ended it.

Both scripts now only touch running VMs, and the second run kept cp-2 and
cp-3 down until I started them.
[#111](https://github.com/guy-with-a-why/telemetry-blackbox/pull/111) has the
fix.

Afterwards I checked what happens when a worker goes instead. I cordoned edge-1
and deleted its echo Pod, and the replacement sat in Pending. echo's
[spread rule](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)
allows at most one Pod more on any node than on the emptiest, and by default a
node echo can't run on still counts as empty. A second Pod on data-1, against
none on edge-1, broke the rule, so the one place it could go was refused.

One line fixes it. `nodeTaintsPolicy: Honor` makes the rule count only nodes
echo can run on, so a cordoned or dead worker and the control planes drop out of
the sum. data-1 stops being measured against nodes it can't use, and the
replacement starts there. Without it, losing a worker would have cost echo half
its Pods until the worker came back. The catch is that the scheduler never moves
a Pod back, so once edge-1 returns, both stay on data-1 until something restarts
one.

Applying that fix rolled echo out again and turned up a second gap: both new
Pods landed on data-1. The rule still counted the old Pods on their way out, so
data-1 never looked fuller than edge-1.

`matchLabelKeys: [pod-template-hash]` changes what gets counted: only Pods from
the same rollout, which share a template hash. Pods from the last rollout stop
steering the new ones, so every rollout ends with one Pod on each worker.
Without it, the spread came down to the timing of the last rollout, and losing
data-1 could have taken echo down entirely.

A re-run proved both fixes: the rollout left one Pod on each worker, and the
cordon put the replacement on data-1 straight away. Neither gap shows while
every node is healthy, which is what drills are for.

## What's next

[#13](https://github.com/guy-with-a-why/telemetry-blackbox/issues/13) snapshots
etcd, deletes a namespace and restores it. A restore rewinds the whole cluster,
so every member has to
[start again from the same snapshot](https://etcd.io/docs/v3.5/op-guide/recovery/).
The fallback is `just up` and twenty minutes. Leg 1 is due on Friday.

## Quiz

Eleven questions on the post, for anyone who wants to check it's landed. Open
one
for my answer.

<details>
<summary>cp-1's etcd was healthy and had every write. Why did it refuse to carry
on alone?</summary>

It couldn't tell dead peers from being cut off, and if cp-2 and cp-3 were alive,
they were a majority that could keep writing. Two majorities always share a
member, so only one side can write, and a write a majority holds survives into
the next leader's log. [Raft](https://raft.github.io/) explains how.

</details>

<details>
<summary>Writes stopped as soon as cp-3 went, but cached reads lasted 22
seconds. Why?</summary>

A plain read must be current, so it goes to etcd, which needs a majority. A read
at `resourceVersion=0` comes from the API server's watch cache in memory, and
that lasted until the address went.

</details>

<details>
<summary>Why does the virtual IP go when quorum does?</summary>

kube-vip renews its Lease through the API every 2 seconds and stands down after
10 without a renewal. Renewing and taking the Lease are both writes, so without
quorum no kube-vip can hold the address.

</details>

<details>
<summary>The echo container crashes while the control plane is down. Does it
come back?</summary>

Yes. The kubelet restarts it locally under
[`restartPolicy: Always`](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#restart-policy),
with no API, and reports the new status once the API is back.

</details>

<details>
<summary>A worker dies while the control plane is down. What happens to its Pod
and its traffic?</summary>

The Pod dies and nothing replaces it, because the ReplicaSet controller and the
scheduler work through the API. Nobody removes it from the Service's endpoints
either, so about half the connections still go to it and time out.

</details>

<details>
<summary>One control plane stops. What does the cluster report, and
when?</summary>

Its kubelet stops renewing its
[node Lease](https://kubernetes.io/docs/concepts/architecture/nodes/#node-heartbeats),
which it does every 10 seconds, and after about 40 to 50 seconds the node goes
NotReady with an unreachable taint. Ordinary Pods are
[evicted after 300 seconds](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/#taint-based-evictions),
while DaemonSet Pods and static Pods stay with the node.

</details>

<details>
<summary>cp-2 came back before cp-3. Why could writes resume, and how does cp-3
catch up?</summary>

Two of three is a majority, so cp-1 and cp-2 elect a leader and commit a write
once both have it. cp-3 is still a member, and the leader sends it what it
missed as log entries, or as a snapshot if the log has moved on.

</details>

<details>
<summary>All three control planes run on one home server. What didn't the
drill prove?</summary>

Anything that hits the host hits all three, such as CPU starvation or one slow
disk under every etcd member. It also didn't test a partition or a slow node,
both harder than a clean stop. In production the three go in separate failure
domains, and
[kubeadm's HA topologies](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/)
weigh where etcd sits.

</details>

<details>
<summary>With edge-1 cordoned, why did echo's replacement Pod sit in
Pending?</summary>

The spread rule counted edge-1 and the control planes as nodes holding no echo
Pods, so a second Pod on data-1 broke `maxSkew: 1`. `nodeTaintsPolicy: Honor`
counts only nodes the Pod could run on.

</details>

<details>
<summary>Why did a rollout put both echo Pods on one worker?</summary>

The spread rule counted every Pod labelled `app=echo`, including the old ones
still running. At each step, data-1 looked no fuller than edge-1.
`matchLabelKeys: [pod-template-hash]` counts only Pods from the same rollout.

</details>

<details>
<summary>Why would Terraform's state go stale here?</summary>

The drills stop and delete VMs outside Terraform, so until the next apply its
state describes a cluster that no longer exists.

</details>
