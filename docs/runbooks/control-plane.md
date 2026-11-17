# Lose one control plane, then two

The cluster runs three control planes and three etcd members. With one gone,
etcd keeps quorum and nothing changes. With two gone, etcd stops, the API
goes with it and the workloads keep serving. This drill shows both.

I ran it twice on 16 November 2026. The first run ended early, for a reason
that had nothing to do with etcd. The [second run](#second-run-16-november-2026)
is the one that counts.

Everything runs on my home server, in two terminals.

## Before I start

- `just cluster-check` passes.
- `just drill-watch` runs in the first terminal. I wait for
  `Start the drill` before I break anything, because it deploys echo first.
- The steps run in the second terminal.
- Both terminals append to one log, so neither overwrites the other:

  ```bash
  just drill-watch 2>&1 | tee -ai drill.log    # first terminal
  just cluster-check 2>&1 | tee -a drill.log   # every check below
  ```

  `-i` keeps `tee` alive through Ctrl-C, so the summary lands too.
  `cluster-check` prints its failures to stderr, hence `2>&1`.

`drill-watch` prints a line whenever something changes: which control planes
are up, which one holds the VIP and whether echo, a read, a cached read and a
write succeed. `deploy/README.md` explains each probe.

## Steps

### 1. Lose one control plane

```bash
multipass stop --force cp-2
```

`--force` pulls the power. A clean shutdown would let etcd hand over
leadership politely, and real failures don't.

Two of three members is still a majority, so etcd keeps writing. If cp-2 held
the VIP, kube-vip on another control plane takes it once the 15 s Lease runs
out. Every probe stays `ok`, apart from a gap while the VIP moves.

### 2. Check it

After a minute, so the node controller has noticed:

```bash
just cluster-check
```

It fails, and should: kube-vip isn't ready on cp-2, four of five nodes are
Ready and two of three etcd members are healthy. The API still answers on the
VIP.

### 3. Lose a second

```bash
multipass stop --force cp-3
```

One of three is not a majority. etcd can't elect a leader, so it refuses
writes and consistent reads. cp-1's API server stops being ready, but it
still answers reads at `resourceVersion=0` from its watch cache.

kube-vip renews its Lease through that API, every 2 s, and stands down if it
can't renew for 10 s. So the VIP disappears, and the cached reads go with it.
The API doesn't stay read-only. It goes away.

echo keeps answering. The Pods run on the workers, and kube-proxy's iptables
rules stay in the kernel. Nothing on the data path needs the control plane
until something changes.

### 4. Check it

```bash
just cluster-check
```

It stops before it reaches the API:

```text
no control plane's API server is ready (running: cp-1): kubeadm init hasn't run, or etcd has lost quorum
```

It only asks running VMs. The first run shows why that matters.

### 5. Bring both back

```bash
multipass start cp-2 cp-3
```

Once a second member is up, etcd has a majority again and elects a leader.
The API comes back, kube-vip takes its Lease and the VIP returns. The
`drill-watch` lines go back to `ok`.

### 6. Prove it

Ctrl-C in the first terminal prints how many probes of each kind passed.
Then:

```bash
just cluster-check
```

Cilium on the two rebooted nodes takes a minute to be ready, so the first
check may fail on it alone.

## What I saw

### First run, 16 November 2026

Stage one went as expected: cp-2 stopped and the cluster carried on without
it.

Stage two lasted about a minute. cp-3 went at 19:53:13. 32 s later, the
API dropped `drill-watch`'s connection, and from 19:53:50 the VIP didn't
answer at all:

```text
E1116 19:53:50.592902 ... dial tcp 10.97.0.250:6443: connect: no route to host
```

That's kube-vip standing down, as step 3 predicts. Then I ran
`just cluster-check`, and afterwards all five VMs were running. I hadn't
started any of them. Multipass's log, trimmed:

```text
Nov 16 19:53:13 multipassd: started: qemu-img snapshot -l .../instances/cp-3/...
Nov 16 19:54:00 multipassd: started: qemu-system-x86_64 ... .../instances/cp-2/...
Nov 16 19:54:20 multipassd: started: qemu-system-x86_64 ... .../instances/cp-3/...
```

`cluster-check` looked for a ready API server by running `multipass exec` on
each control plane in turn. cp-1 wasn't ready, because etcd had no quorum, so
it moved on to cp-2 and cp-3. `multipass exec` starts a stopped instance and
retries. Its help doesn't say so, but `exec.cpp` does. The check booted cp-2,
waited 20 s for it, then booted cp-3. The tool meant to report the outage
ended it.

`drill-watch` never reached its loop. It was still waiting for echo to roll
out when I stopped cp-3, and it timed out once the API went.

Both scripts now only touch running VMs, and `drill-watch` reads the VIP
holder from `multipass list`. It also says when to start.

### Second run, 16 November 2026

With both fixes in:

```text
20:16:10  +   1s  up cp-1,cp-2,cp-3  vip cp-1  echo ok  read ok  cache ok  write ok
20:16:20  +  11s  up cp-1,cp-3  vip cp-1  echo ok  read ok  cache ok  write ok
20:16:58  +  49s  up cp-1  vip cp-1  echo ok  read fail  cache ok  write fail
20:17:20  +  71s  up cp-1  vip none  echo ok  read fail  cache fail  write fail
20:19:46  + 217s  up cp-1,cp-2,cp-3  vip none  echo ok  read fail  cache fail  write fail
```

Losing cp-2 changed nothing. cp-1 held the VIP, so there was nothing to move.

Losing cp-3 stopped consistent reads and writes on the next probe. The API
server kept serving cached reads for another 22 s, until kube-vip stood down
and the VIP went. echo didn't notice.

`cluster-check` stopped early and left cp-2 and cp-3 stopped:

```text
no control plane's API server is ready (running: cp-1): kubeadm init hasn't run, or etcd has lost quorum
```

Both were back by 20:19:46. I stopped `drill-watch` before quorum returned:

```text
echo: 79 of 79 passed
read: 29 of 79 passed
cache: 35 of 79 passed
write: 29 of 79 passed
```

echo answered every probe. Cached reads outlived consistent ones by six
probes. With probes timing out, a round took about 3 s, not 1.

Then `cluster-check`:

```text
API on 10.97.0.250: ok, held by cp-1
kube-vip: running on 3 control planes, all reading admin.conf
nodes: 5 of 5 Ready
etcd: 3 of 3 members healthy
cilium: ready on 3 of 5 nodes
```

etcd, the API and kube-vip were back. Cilium on cp-2 and cp-3 was still
starting. Once it was ready:

```text
API on 10.97.0.250: ok, held by cp-1
kube-vip: running on 3 control planes, all reading admin.conf
nodes: 5 of 5 Ready
etcd: 3 of 3 members healthy
cilium: ready on 5 nodes
```

The check after stage one is missing. `drill-watch` wrote through `tee -i`
without `-a`, so it wrote over what the check had appended.

### What else the drill found

echo is meant to keep one Pod on each worker, so losing either leaves one
serving. Two checks after the drill showed its spread rule didn't hold that.

**A lost worker's Pod couldn't be replaced.** I cordoned edge-1 and deleted its
echo Pod. The replacement sat in Pending:

```text
0/5 nodes are available: 1 node(s) didn't match pod topology spread constraints, 1 node(s) were unschedulable, 3 node(s) had untolerated taint(s).
```

The rule allows at most one Pod more on any node than on the emptiest. By
default it counts every node, tainted ones included, so cordoned edge-1 and the
three control planes each counted as holding none. A second Pod on data-1 broke
the rule. A dead worker is tainted the same way. `nodeTaintsPolicy: Honor`
leaves tainted nodes out of the count.

**A rollout put both Pods on one worker.** Applying that fix rolled echo out
again, and both new Pods landed on data-1 (columns trimmed):

```text
NAME                    READY   STATUS        RESTARTS   AGE   IP             NODE
echo-5976856569-r52d5   1/1     Terminating   0          18m   10.244.3.87    edge-1
echo-7bbd856f5b-ddzh8   1/1     Running       0          16s   10.244.5.176   data-1
echo-7bbd856f5b-v7z4q   1/1     Running       0          4s    10.244.5.2     data-1
```

The rule counts every Pod labelled `app=echo`, old ones included. A rollout
replaces them one at a time, so at each step the old Pods still running made
data-1 look no fuller than edge-1. `matchLabelKeys: [pod-template-hash]` counts
only Pods from the same rollout.

The rule now reads:

```yaml
topologySpreadConstraints:
  - maxSkew: 1                         # at most one Pod more than the emptiest node
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    nodeTaintsPolicy: Honor            # cordoned, dead and control-plane nodes don't count
    matchLabelKeys:
      - pod-template-hash              # only this rollout's Pods count
    labelSelector:
      matchLabels:
        app: echo
```

With both in place, a rollout left one Pod on each worker, and the same cordon
put the replacement on data-1 straight away:

```text
NAME                    READY   STATUS    RESTARTS   AGE   IP             NODE
echo-5cb4c8bc96-5brtt   1/1     Running   0          52s   10.244.5.133   data-1
echo-5cb4c8bc96-vblxj   1/1     Running   0          22s   10.244.5.18    data-1
```

The scheduler never moves a running Pod, so after the uncordon both stayed on
data-1. `kubectl -n drill rollout restart deployment/echo` spreads them again.

Neither causes trouble while every node is healthy, which is why a drill is the
place to find them.

## Why three or five

etcd writes only when a majority of members agree. Quorum is ⌊n/2⌋ + 1.

| Members | Quorum | Can lose |
|---|---|---|
| 1 | 1 | 0 |
| 2 | 2 | 0 |
| 3 | 2 | 1 |
| 4 | 3 | 1 |
| 5 | 3 | 2 |

Even sizes buy nothing. Four members survive one loss, like three, but give
one more machine to fail, and every write waits for three acknowledgements
instead of two. Two is worse than one, because losing either stops writes.

Partitions decide it. Four members can split two and two, and then neither
side has a majority and the cluster stops. Split three or five in two and
one side always keeps a majority. The majority rule itself is what stops a
split brain: two halves can't both accept writes, because only one of them
can be a majority.

## When it goes wrong

### A control plane won't rejoin etcd

`--force` is a power cut. etcd syncs every commit to disk, but a cut
mid-write can leave its log or database torn. On restart, `etcd-cp-N` crashes
in a loop and the kubelet keeps restarting it.

I remove the member and join the node again. That only works for cp-2 and
cp-3: after a reset, `cluster-up` would run `kubeadm init` on cp-1 and build
a new, empty cluster. If cp-1 is the broken one, I join it by hand with step
5 of the bootstrap runbook.

From a healthy control plane, I find the member's ID with `member list` and
remove it with `member remove`, using the flags in
[`bootstrap.md`](bootstrap.md#a-join-failed-halfway). Then:

```bash
kubectl delete node cp-N
multipass exec cp-N -- sudo kubeadm reset -f
just cluster-up
```

`cluster-up` treats a control plane as joined once its Node is labelled, so
the Node has to go before it will join cp-N again.

### A node comes back on a new address

Each etcd member's peer URL and certificate name the node's IP. A new address
means the others can't reach it, or won't trust it. Multipass never expires a
lease, so it shouldn't happen here, but on real hardware it's the classic
case. The fix is the same: remove, reset and join.

### The VIP doesn't come back

kube-vip needs a working API to take its Lease, so the VIP returns after
quorum, not before. If etcd is healthy and the VIP is still missing, I read
kube-vip's log on a control plane:

```bash
multipass exec cp-1 -- sudo crictl logs --tail 50 \
  $(multipass exec cp-1 -- sudo crictl ps -a -q --latest --name kube-vip)
```

### What I don't do

With two members down, `etcd --force-new-cluster` on the survivor gets writes
going again. The other two then come back with history the new cluster
doesn't share, and both have to be wiped and joined again. It's for members
that are never coming back, not ones that are slow.
