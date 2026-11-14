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

`just host` runs three containers on the host, and `just vms` starts them
first. All of them listen on the `zone1` bridge, where only the VMs can reach
them.

![just vms starts three containers on the host, then launches five Multipass VMs with node.yaml as cloud-init. The VMs pull images from the registry and the registry.k8s.io mirror, and packages from apt-cacher-ng. Only the mirror and the cache reach the internet, on the first fetch.](../docs/diagrams/host.svg)

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
- **A `registry:2` mirror of `registry.k8s.io`**, in proxy mode on port 5001,
  serves the control-plane images. containerd tries it first and falls back to
  `registry.k8s.io` if it's down.

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
