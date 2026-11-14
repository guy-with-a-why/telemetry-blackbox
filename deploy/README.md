# Deploy

Everything that builds the VMs and the cluster, then runs the stack on it:
cloud-init for the VMs, kubeadm configuration and the manifests.

## The VMs

```bash
just vms          # the registry, then five VMs
just vms-check    # every node is ready for kubeadm and pulls from the registry
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

That leaves about 5 GB for the host, the registry and Renode. Ten vCPUs on
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

## The local registry

`just registry` runs `registry:2` in Docker on the host. It listens in two
places:

- `localhost:5000`, where I push. Docker allows plain HTTP to localhost
  without any daemon config.
- The `zone1` bridge address, port 5000, where the VMs pull.

containerd on every node maps `localhost:5000` to the bridge address, so a
Pod names the image exactly as I pushed it. Plain HTTP is fine on a private
bridge and wrong anywhere else. [ADR 5](../docs/adr/0005-just-mise-and-a-local-registry.md)
has the reasoning.
