# Deploy

Everything that builds the VMs and the cluster, then runs the stack on it:
cloud-init for the VMs, kubeadm configuration and the manifests.

## The VMs

```bash
just vms          # the host services, then five VMs
just vms-check    # every node is ready for kubeadm and uses the host services
just vms-delete   # all five, and their disks
```

[`vms/config.sh`](vms/config.sh) holds the shape of the cluster: the nodes,
their sizes, the zone and the Kubernetes version. The scripts all read it.

Every node boots from one file, [`vms/node.yaml`](vms/node.yaml). It loads
`overlay` and `br_netfilter`, sets the sysctls, turns swap off, installs
containerd with systemd cgroups and holds kubeadm, kubelet and kubectl at
1.36. The latest is 1.37, so there's an upgrade to practise.

All five sit in one Multipass zone, `zone1`, so they share a subnet. kube-vip
answers ARP for the API's virtual IP, and ARP doesn't cross a router.

## The memory budget

The VMs run on my home server: 4 cores, 16 GB of memory and plenty of disk.
My laptop has the same memory but its desktop takes too much of it, and its
disk is nearly full.

| Node | vCPUs | Memory | Disk | Runs |
|---|---|---|---|---|
| cp-1, cp-2, cp-3 | 2 each | 1.5 GB each | 10 GB each | API server, etcd, scheduler, controller manager |
| edge-1 | 2 | 2 GB | 10 GB | the gateway |
| data-1 | 2 | 4 GB | 40 GB | Redpanda, the pipeline, ClickHouse, Grafana |
| **Total** | **10** | **10.5 GB** | **80 GB** | |

That leaves about 5 GB for the host, its services and Renode. Ten vCPUs on
four cores is overcommitted, which is fine at idle and slow during bootstrap.
Two is the floor, because kubeadm checks a control plane has two CPUs.

### Why the kubeadm memory check is skipped

kubeadm's preflight wants 1700 MB on a control plane, and mine have 1.5 GB.
That floor is generic. It isn't a measurement of a five-node cluster with a
few dozen Pods, where etcd and the API server stay small. The memory does
more good on data-1, where Redpanda and ClickHouse live.

So #11 skips that one check with `--ignore-preflight-errors=Mem`, and every
other check still runs. If a control plane starts swapping or getting
OOM-killed, the fix is to move memory from data-1, not to drop a node.

## What the host runs

`just host` runs five containers on the host, and `just vms` starts them
first. All of them listen on the `zone1` bridge, where only the VMs can reach
them.

![just vms starts five containers on the host, then launches five Multipass VMs with node.yaml as cloud-init. The VMs pull images from the registry and the mirrors of registry.k8s.io, quay.io and ghcr.io, and packages from apt-cacher-ng. Only the mirrors and the cache reach the internet, on the first fetch.](../docs/diagrams/host.svg)

### The local registry

`registry:2` listens in two places:

- `localhost:5000`, where I push. Docker allows plain HTTP to localhost
  without any daemon config.
- The `zone1` bridge address, port 5000, where the VMs pull.

containerd on every node maps `localhost:5000` to the bridge address, so a
Pod names the image exactly as I pushed it. Plain HTTP is fine on a private
bridge and wrong anywhere else. [ADR 5](../docs/adr/0005-just-mise-and-a-local-registry.md)
has the reasoning.

### The caches

The first build took 18 minutes. My home server's internet connection
downloads at about 1.1 MB/s, and each VM fetched the same 169 MB of packages, so five VMs pulled
845 MB of identical bytes. Launching them in parallel wouldn't help, because
they'd share the same connection. Caching does.

- **apt-cacher-ng** sits in front of the Ubuntu archive and `pkgs.k8s.io`.
  apt's sources point straight at it, with the real host first in the path,
  for example `http://<bridge>:3142/pkgs.k8s.io/core:/stable:/v1.36/deb/`.
  Proxy mode trips over the colons in the Kubernetes paths. apt still checks
  every package against the repository's signing key, and the key itself comes
  straight from upstream.
- **`registry:2` mirrors** in proxy mode serve the images from upstream
  registries. Each mirrors one upstream: `registry.k8s.io` on port 5001 for
  the control plane, `quay.io` on 5002 for Cilium and `ghcr.io` on 5003 for
  kube-vip. containerd tries the mirror first and falls back upstream if it's
  down.

Both keep their data in Docker volumes, so a rebuild after `just vms-delete`
barely touches the internet.

| Build | Time |
|---|---|
| No cache | 18m 06s |
| Empty cache | 8m 36s |
| Warm cache | 6m 09s |

With a warm cache, a VM finishes cloud-init in about a minute, and packages
arrive at 75 to 100 MB/s. What's left is booting and unpacking, one VM at a
time. Launching them in parallel is the next step if a rebuild still hurts.

## The cluster

I bootstrap the cluster by hand with kubeadm. The files it needs are in
[`cluster/`](cluster/).

1. `just cluster-files` fills them in and copies them to `~/cluster/` on the
   control planes.
2. On cp-1, kube-vip goes into `/etc/kubernetes/manifests` reading
   `super-admin.conf`, then `kubeadm init --upload-certs`, then kube-vip goes
   back to `admin.conf`.
3. cp-2 and cp-3 join with `--control-plane` and
   `--ignore-preflight-errors=Mem`, then get kube-vip.
4. edge-1 and data-1 join as workers.
5. Cilium goes on from my laptop.
6. `just cluster-check` checks the VIP, kube-vip on each control plane
   reading `admin.conf`, every node Ready, a healthy etcd member on each
   control plane and Cilium on every node.

```bash
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.4 \
  -n kube-system -f deploy/cluster/cilium-values.yaml
```

- [`kubeadm.yaml`](cluster/kubeadm.yaml) sets the control-plane endpoint to the
  virtual IP, so every kubeconfig and every join goes through it.
- [`kube-vip.yaml`](cluster/kube-vip.yaml) is a static Pod on each control
  plane. One of them holds the virtual IP and answers ARP for it. If that node
  goes down, another takes the lease and the IP.
- [`cilium-values.yaml`](cluster/cilium-values.yaml) gives Cilium the pod
  network. kube-proxy stays and routes Services.

### The addresses

| Range | Value | Why |
|---|---|---|
| Nodes | `10.97.0.0/24` | The `zone1` bridge, from Multipass |
| API virtual IP | `10.97.0.250` | On the bridge, because ARP doesn't cross a router |
| Pods | `10.244.0.0/16` | Cilium's default, `10.0.0.0/8`, covers the bridge |
| Services | `10.96.0.0/16` | kubeadm's default, `10.96.0.0/12`, covers the bridge |

Multipass's DHCP range covers the whole bridge and never expires a lease, so
nothing reserves the virtual IP. Both recipes fail if a VM ever leases it.

### Reaching the API from my laptop

The virtual IP lives on my home server's bridge, so my laptop reaches it
through an SSH tunnel. The API server's certificate also names `127.0.0.1`
for this.

```bash
ssh -fN -L 6443:10.97.0.250:6443 <home-server>
```

My kubeconfig is cp-1's `admin.conf` with the server changed to
`https://127.0.0.1:6443`.
