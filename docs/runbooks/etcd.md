# Snapshot and restore etcd

etcd holds every object in the cluster. A snapshot is a copy of one member's
database, and restoring it puts the whole cluster back to that moment. This
drill takes a snapshot, deletes a namespace and restores it.

I ran it twice on 17 November 2026. The first time I worked out each step as I
went, and reads failed for 19 minutes. The [second run](#second-run-17-november-2026)
follows these steps, and reads failed for under two minutes.

Everything runs on my home server, in two terminals.

## Before I start

- `just cluster-check` passes.
- No control plane has a `/var/lib/etcd.old` left from an earlier drill. Step 5
  keeps an existing one as its fallback.
- `just drill-watch` runs in the first terminal. I wait for
  `Start the drill`, because it deploys echo and the `drill` namespace first.
- The steps run in the second terminal, with the cluster's kubeconfig:

  ```bash
  export KUBECONFIG=~/.kube/blackbox.conf
  ```

  `~/.kube/config` on the server is an empty stub, and kubectl asks for a
  username without this.
- Both terminals append to one log:

  ```bash
  just drill-watch 2>&1 | tee -ai drill.log    # first terminal
  just cluster-check 2>&1 | tee -a drill.log   # every check below
  ```

## Steps

### 1. Take a snapshot

```bash
just etcd-snapshot
```

It saves the snapshot on the first running control plane, copies it to
`~/.local/state/telemetry-blackbox/etcd/` and checks the copy's hash. It prints
the revision, which is the point the restore goes back to.

### 2. Delete the namespace

```bash
kubectl delete namespace drill
```

The namespace, its Pods and its ConfigMap go. echo fails, then reads and writes
of the ConfigMap fail, because it no longer exists. The API is still up.

### 3. Copy the snapshot to every control plane

Multipass is a snap and can't read dot-directories, so `multipass transfer`
needs a copy in my home directory first:

```bash
snap=$(ls -t ~/.local/state/telemetry-blackbox/etcd/*.db | head -1) && sha256sum "$snap"
install -m 600 "$snap" ~/etcd-restore.db
for cp in cp-1 cp-2 cp-3; do
  multipass transfer ~/etcd-restore.db "$cp:/home/ubuntu/etcd-restore.db" &&
  multipass exec "$cp" -- chmod 600 /home/ubuntu/etcd-restore.db
done
for cp in cp-1 cp-2 cp-3; do echo "$cp $(multipass exec "$cp" -- sha256sum /home/ubuntu/etcd-restore.db)"; done
rm ~/etcd-restore.db
```

Every hash must match the first. I never restore from a copy that doesn't. The
copies hold every Secret, so only `ubuntu` can read them, and step 8 removes
them.

### 4. Stop etcd and the API servers

```bash
for cp in cp-1 cp-2 cp-3; do
  multipass exec "$cp" -- sudo mv /etc/kubernetes/manifests/etcd.yaml \
    /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/
done
```

The kubelet stops a static Pod when its manifest leaves the directory. I wait
until no IDs follow the names:

```bash
for cp in cp-1 cp-2 cp-3; do echo "$cp: $(multipass exec "$cp" -- sudo crictl ps -q --name '^(etcd|kube-apiserver)$')"; done
```

kube-vip can't renew its Lease without an API, so the VIP goes too.

### 5. Restore every member

```bash
cluster='cp-1=https://10.97.0.54:2380,cp-2=https://10.97.0.213:2380,cp-3=https://10.97.0.153:2380'
declare -A ip=([cp-1]=10.97.0.54 [cp-2]=10.97.0.213 [cp-3]=10.97.0.153)
restore() {
  local cp=$1 image
  image=$(multipass exec "$cp" -- sudo awk '/image:/ { print $2 }' /etc/kubernetes/etcd.yaml)
  multipass exec "$cp" -- sudo sh -c 'test -d /var/lib/etcd.old || mv /var/lib/etcd /var/lib/etcd.old; rm -rf /var/lib/etcd' &&
  multipass exec "$cp" -- sudo ctr -n k8s.io run --rm \
    --mount type=bind,src=/var/lib,dst=/var/lib,options=rbind:rw \
    --mount type=bind,src=/home/ubuntu,dst=/home/ubuntu,options=rbind:ro \
    "$image" etcd-restore \
    etcdutl snapshot restore /home/ubuntu/etcd-restore.db \
      --data-dir /var/lib/etcd --name "$cp" \
      --initial-advertise-peer-urls "https://${ip[$cp]}:2380" \
      --initial-cluster "$cluster" \
      --bump-revision 1000000000 --mark-compacted
}
for cp in cp-1 cp-2 cp-3; do restore "$cp" || { echo "restore failed on $cp"; break; }; done
```

Each node prints `restored snapshot`. If one fails, `restore cp-N` runs it
again on that node. It keeps the first `etcd.old`, so the data from before the
restore survives a second attempt.

`etcdutl` isn't installed on the nodes, so `ctr` runs it from the etcd image
that's already there. The tag comes from the moved manifest, so it follows
upgrades.

Every node gets the same `--initial-cluster`. etcd derives the cluster ID and
the member IDs from it, so all three agree on who's in the cluster. The
manifests are no help here: kubeadm grew the cluster one join at a time, so
cp-1's lists only cp-1. Each node's own `--name` and peer URL say which member
it is.

The snapshot is older than anything the API servers, kubelets and controllers
last saw. Without `--bump-revision`, new writes would reuse revisions they'd
already seen, so they'd miss them. With it, revisions only go forward, and
`--mark-compacted` puts everything older below the compaction mark. Anything
watching from an old resourceVersion gets 410 Gone and lists again.

The Kubernetes docs also restart the scheduler, the controller manager and the
kubelets after a restore. I don't, because the compaction mark makes every
watcher list again, and the second run shows it's enough here.

### 6. Start etcd, then the API servers

```bash
for cp in cp-1 cp-2 cp-3; do multipass exec "$cp" -- sudo mv /etc/kubernetes/etcd.yaml /etc/kubernetes/manifests/; done
```

I wait until all three members are healthy. This checks from cp-1:

```bash
multipass exec cp-1 -- sudo sh -c 'crictl exec $(crictl ps -q --name "^etcd$") etcdctl \
  --endpoints https://127.0.0.1:2379 --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key /etc/kubernetes/pki/etcd/healthcheck-client.key endpoint health --cluster'
```

Then the API servers:

```bash
for cp in cp-1 cp-2 cp-3; do multipass exec "$cp" -- sudo mv /etc/kubernetes/kube-apiserver.yaml /etc/kubernetes/manifests/; done
```

kube-vip takes its Lease again and the VIP returns.

### 7. Prove it

```bash
just cluster-check
kubectl get namespace drill -o jsonpath='{.metadata.uid} {.metadata.creationTimestamp}{"\n"}'
kubectl -n drill get pods -o wide
```

The namespace has its old UID and creation time, so it's the same object, not
a new one. The Pods have their old names. The kubelets build new sandboxes for
them, and echo answers.

### 8. Clean up

Once `cluster-check` passes:

```bash
for cp in cp-1 cp-2 cp-3; do multipass exec "$cp" -- sudo rm -rf /var/lib/etcd.old /home/ubuntu/etcd-restore.db; done
```

## What I saw

### First run, 17 November 2026

I worked out each step as I ran it. Reads failed for 19 minutes, from 20:10:47
to 20:29:37:

```text
20:09:54  +   1s  up cp-1,cp-2,cp-3  vip cp-3  echo ok  read ok  cache ok  write ok
20:10:42  +  49s  up cp-1,cp-2,cp-3  vip cp-3  echo fail  read ok  cache ok  write ok
20:10:47  +  54s  up cp-1,cp-2,cp-3  vip cp-3  echo fail  read fail  cache fail  write fail
20:17:24  + 451s  up cp-1,cp-2,cp-3  vip none  echo fail  read fail  cache fail  write fail
20:29:37  +1184s  up cp-1,cp-2,cp-3  vip none  echo fail  read ok  cache ok  write ok
20:29:40  +1187s  up cp-1,cp-2,cp-3  vip cp-3  echo fail  read ok  cache ok  write ok
20:30:17  +1224s  up cp-1,cp-2,cp-3  vip cp-3  echo ok  read ok  cache ok  write ok
```

Most of it went on working out each step: the kubeconfig, getting the snapshot
onto the nodes and the restore flags.

### Second run, 17 November 2026

The snapshot came from cp-1 at revision 1000382584. The first run had already
bumped it by a billion.

```text
+----------+------------+------------+------------+---------+
|   HASH   |  REVISION  | TOTAL KEYS | TOTAL SIZE | VERSION |
+----------+------------+------------+------------+---------+
| d31b1f50 | 1000382584 |        482 |      15 MB |   3.6.0 |
+----------+------------+------------+------------+---------+
```

`VERSION` is the storage format, not the binary, which is 3.6.8.

`drill-watch`:

```text
20:38:13  +   1s  up cp-1,cp-2,cp-3  vip cp-3  echo ok  read ok  cache ok  write ok
20:38:47  +  35s  up cp-1,cp-2,cp-3  vip cp-3  echo fail  read ok  cache ok  write ok
20:38:55  +  43s  up cp-1,cp-2,cp-3  vip cp-3  echo fail  read fail  cache fail  write fail
20:39:43  +  91s  up cp-1,cp-2,cp-3  vip none  echo fail  read fail  cache fail  write fail
20:40:47  + 155s  up cp-1,cp-2,cp-3  vip none  echo fail  read ok  cache ok  write ok
20:40:50  + 158s  up cp-1,cp-2,cp-3  vip cp-3  echo fail  read ok  cache ok  write ok
20:41:53  + 221s  up cp-1,cp-2,cp-3  vip cp-3  echo ok  read ok  cache ok  write ok
```

| Time | Step | Took |
|---|---|---|
| 20:38:40 | Delete the namespace | 14 s |
| 20:39:05 | Copy the snapshot, three hashes match | 9 s |
| 20:39:14 | Stop etcd and the API servers | 36 s |
| 20:40:04 | Restore three members | 10 s |
| 20:40:24 | Start etcd, three members healthy | 6 s |
| 20:40:30 | Start the API servers, reads work through the VIP | 17 s |

From stopping the API servers to reads working again took 93 seconds. Until
the API servers stopped, from 20:39:14, the reads failed because the ConfigMap
was gone, not the API. `drill-watch` can't tell the two apart. `multipass list`
reported the VIP 3 s after the API answered on it.

echo came back about a minute after the API. The Pods had their old names and
new addresses, because the kubelets built new sandboxes for them (columns
trimmed):

```text
NAME                    READY   STATUS    RESTARTS   AGE   IP             NODE
echo-58849b6468-7cmc8   1/1     Running   1          32m   10.244.3.252   edge-1
echo-58849b6468-bdwz7   1/1     Running   1          32m   10.244.5.199   data-1
```

The namespace kept the UID and creation time it got in the first run, at
20:09:40. The ConfigMap's resourceVersion read 2000383099, two bumps on.

```text
echo: 33 of 102 passed
read: 69 of 102 passed
cache: 69 of 102 passed
write: 69 of 102 passed
```

Then `cluster-check`:

```text
API on 10.97.0.250: ok, held by cp-3
kube-vip: running on 3 control planes, all reading admin.conf
nodes: 5 of 5 Ready
etcd: 3 of 3 members healthy
cilium: ready on 5 nodes
```

## What a restore costs

A restore can't bring back one namespace. It puts every object back to the
snapshot. Anything written after it is lost: new Deployments, scaling, Secrets,
Leases and Node heartbeats. Here that was a few minutes of a quiet cluster, so
nothing mattered. On a busy cluster a restore is the last resort, not an undo.

The snapshot holds every Secret in plain text. `etcd-snapshot` leaves it
readable only by me, and it never goes in the repo. Step 3's copies on the
control planes last until step 8.

## Why every member

One member restored alone gets a new cluster ID from the restore. The other two
still have the old one, so they reject it. Restoring all three from one file,
with one `--initial-cluster`, makes a new cluster whose members agree from the
start.

## When it goes wrong

### A copy is torn

My first attempt piped the snapshot into `multipass exec`. It arrived as 2.2 MB
of 15 MB, and `etcdutl` refused it:

```text
Error: snapshot missing hash but --skip-hash-check=false
```

Every snapshot ends in a hash of its contents, so a truncated copy fails
safely. `multipass transfer` and the hash check in step 3 keep it from
happening.

### A member won't start

If an etcd container crashes after step 6, I go back to the data from before
the restore. I stop etcd and the API servers with step 4, run this, then start
them with step 6:

```bash
for cp in cp-1 cp-2 cp-3; do multipass exec "$cp" -- sudo sh -c 'rm -rf /var/lib/etcd && mv /var/lib/etcd.old /var/lib/etcd'; done
```

That's the cluster as it was before the restore, with the namespace still
deleted. Always all three, never one or two: that's members from two
clusters.

### A member has the wrong `--initial-cluster`

Copied from the manifest, cp-1 would know only itself and start a one-member
cluster of its own. cp-2 and cp-3 would refuse it on the cluster ID. The fix is
steps 4 to 6 again on all three, with the full list. Step 5 is safe to run
twice.

### What I don't do

`etcdctl snapshot restore` no longer exists in etcd 3.6. `etcdutl` replaced it.
I also don't restore while any API server runs, because it would keep serving
from its watch cache and write to a cluster that's changing under it.
