# Bootstrap the cluster by hand

How I bring up the highly available control plane on the five VMs, by hand,
with kubeadm, kube-vip and Cilium. I first ran it on 15 November 2026, and it
took 47 minutes from `kubeadm init` to a clean `just cluster-check`.

The VMs run on my home server. Steps 1 to 6 and step 9 run there, in
the repo or on a VM through `multipass shell`. Steps 7 and 8 run on my laptop.

`just cluster-up` runs steps 1 to 8 in one go on the server, and `just up`
rebuilds the VMs and the cluster from nothing. This runbook is what they do,
and how to recover when they stop halfway. The script runs the joins in steps
5 and 6 from `deploy/cluster/join-control-plane.yaml` and `join-worker.yaml`
in place of the flags.

## Before I start

- `just vms` has built all five VMs, and `just vms-check` passes.
- The server's checkout is on the branch I'm testing, with no stray edits.
- I have two hours free. The certificate key from step 4 expires after two
  hours, and the join token after 24.

## Steps

### 1. Write the files

```bash
just cluster-files
```

This renders `deploy/cluster/` and copies `kubeadm.yaml` to cp-1 and
`kube-vip.yaml` to all three control planes, under `~/cluster/`. It fails if a
VM has leased the virtual IP. `kubeadm.yaml` carries a fresh bootstrap token
and certificate key, so the join commands init prints use them.

### 2. Put kube-vip on cp-1, on ground power

On cp-1:

```bash
sudo cp ~/cluster/kube-vip.yaml /etc/kubernetes/manifests/
sudo sed -i 's#path: /etc/kubernetes/admin.conf#path: /etc/kubernetes/super-admin.conf#' /etc/kubernetes/manifests/kube-vip.yaml
```

Since Kubernetes 1.29, `admin.conf` has no rights until init finishes, and
kube-vip has to hold the virtual IP before then. So it borrows
`super-admin.conf`. The `sed` only changes the `hostPath` line, because
`mountPath:` has a capital P.

### 3. Initialise the first control plane

On cp-1:

```bash
sudo kubeadm init --config ~/cluster/kubeadm.yaml --upload-certs
```

I keep both join commands it prints. The control-plane one carries
`--certificate-key`, which unlocks the shared certificates for two hours.

### 4. Take kube-vip off ground power

On cp-1, straight after init:

```bash
sudo sed -i 's#path: /etc/kubernetes/super-admin.conf#path: /etc/kubernetes/admin.conf#' /etc/kubernetes/manifests/kube-vip.yaml
```

The kubelet sees the file change and restarts kube-vip on `admin.conf`.
`super-admin.conf` is in `system:masters`, which skips RBAC, so nothing should
run on it once init is done. `cluster-check` fails if anything still does.

### 5. Join cp-2 and cp-3

On each, using the control-plane join command from step 3:

```bash
sudo kubeadm join 10.97.0.250:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane --certificate-key <key> \
  --ignore-preflight-errors=Mem
sudo cp ~/cluster/kube-vip.yaml /etc/kubernetes/manifests/
```

kube-vip goes in after the join. Before it, the node has no `admin.conf`.
The control planes have 1.5 GB against kubeadm's 1.7 GB floor, so the memory
check is skipped. `deploy/README.md` has the reasoning.

### 6. Join the workers

On edge-1 and data-1, using the worker join command from step 3:

```bash
sudo kubeadm join 10.97.0.250:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

Every node now shows NotReady. That's expected until step 9.

### 7. Copy the kubeconfig to my laptop

On my laptop:

```bash
ssh <home-server> multipass exec cp-1 -- sudo cat /etc/kubernetes/admin.conf > ~/.kube/config
ssh -fN -L 6443:10.97.0.250:6443 <home-server>
```

Then I change `server:` in `~/.kube/config` to `https://127.0.0.1:6443`. The
API server's certificate names `127.0.0.1` for this tunnel.

`just kubeconfig <home-server>` does both, into `~/.kube/blackbox.conf`.

### 8. Install Cilium

On my laptop:

```bash
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.4 \
  -n kube-system -f deploy/cluster/cilium-values.yaml
```

On a cold mirror, the agents sit at `Init:0/6` for a while. On the first run,
all five nodes pulled the images through quay.io at about 1 MB/s, and it took
over twenty minutes.

### 9. Prove it

On the server:

```bash
just cluster-check
```

## What I saw on the first run

At T+17, every control-plane Pod was running, while Cilium waited for its
images, CoreDNS was Pending and every node was NotReady:

```text
NAME                               READY   STATUS              RESTARTS   AGE
cilium-2d88w                       0/1     Init:0/6            0          110s
cilium-envoy-fcxq9                 0/1     ContainerCreating   0          110s
cilium-operator-6c4c574b46-d8mtq   0/1     ContainerCreating   0          110s
coredns-589f44dc88-h6nzh           0/1     Pending             0          17m
etcd-cp-1                          1/1     Running             0          17m
etcd-cp-2                          1/1     Running             0          7m40s
etcd-cp-3                          1/1     Running             0          8m46s
kube-vip-cp-1                      1/1     Running             0          16m
kube-vip-cp-2                      1/1     Running             0          7m40s
kube-vip-cp-3                      1/1     Running             0          7m26s
```

That's an excerpt of the 34 Pods. `kube-vip-cp-1` is a minute younger than
`etcd-cp-1` because step 4 restarted it.

Once Cilium was up, `cluster-check` passed:

```text
API on 10.97.0.250: ok, held by cp-3
kube-vip: running on 3 control planes, all reading admin.conf
nodes: 5 of 5 Ready
etcd: 3 of 3 members healthy
cilium: ready on 5 nodes
```

The address had moved to cp-3 on its own. At 13:36, with the server flat out,
cp-1's API server stopped answering in time and its leaders lost their Leases.
cp-3 took over, as designed.

## When it goes wrong

### The certificate key has expired

A control-plane join fails after two hours. On a working control plane:

```bash
sudo kubeadm init phase upload-certs --upload-certs
sudo kubeadm token create --print-join-command --certificate-key <new key>
```

The first prints a new key, and the second prints a full control-plane join
command that uses it.

### The join token has expired

After 24 hours, a worker join fails. On a control plane:

```bash
sudo kubeadm token create --print-join-command
```

### A join failed halfway

On the failed node:

```bash
sudo kubeadm reset -f
```

Then I join again. If it was a control plane that got as far as etcd, I
remove its stale member first, from a healthy control plane:

```bash
kubectl -n kube-system exec etcd-cp-1 -- etcdctl \
  --endpoints https://127.0.0.1:2379 --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key /etc/kubernetes/pki/etcd/healthcheck-client.key \
  member list
```

Then `member remove <ID>` with the same flags.

### cluster-check says kube-vip reads super-admin.conf

Step 4 was missed. I run it on the node that `cluster-check` names.

### Cilium is stuck at Init

I check the events before anything else:

```bash
kubectl -n kube-system get events --sort-by=.lastTimestamp | grep -i cilium
```

`Pulling image` with no errors means a cold mirror. Waiting is the fix, and
the next rebuild reads the images from the host.
