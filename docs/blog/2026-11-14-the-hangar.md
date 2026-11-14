# The hangar: five VMs and two caches

*14 November 2026*

## What was done

The cluster has somewhere to live. `just vms` builds five Ubuntu VMs with Multipass, all from one cloud-init file: three control planes, `edge-1` and `data-1`. Each node comes up with containerd and kubeadm 1.36, one minor behind the latest, so there's an upgrade to practise later. A local registry carries my images in, and `just vms-check` proves every node is ready for kubeadm.

The first full build took 18 minutes. Caches on the host bring that down to 6m 09s once they're warm.

Both pieces are up for review. [#74](https://github.com/guy-with-a-why/telemetry-blackbox/pull/74) builds the VMs and closes [#10](https://github.com/guy-with-a-why/telemetry-blackbox/issues/10). [#78](https://github.com/guy-with-a-why/telemetry-blackbox/pull/78) adds the caches and is stacked on it.

![just vms starts three containers on the host, then launches five Multipass VMs with node.yaml as cloud-init. The VMs pull images from the registry and the registry.k8s.io mirror, and packages from apt-cacher-ng. Only the mirror and the cache reach the internet, on the first fetch.](../diagrams/host.svg)

## Why was it done that way

I started on my laptop and moved within the hour. The VMs need 10.5 GB of memory, and the laptop had 6 GB free and a disk at 95%. My home server has 16 GB and room to spare, but only four cores for ten vCPUs. That's fine at idle, and two vCPUs per node is the floor kubeadm checks for.

The control planes get 1.5 GB, under the 1.7 GB kubeadm's preflight asks for, so [#11](https://github.com/guy-with-a-why/telemetry-blackbox/issues/11) skips that one check. The figure is generic: etcd stays small in a five-node cluster, and the memory does more good on `data-1`, where Redpanda and ClickHouse will run.

I weighed the infrastructure-as-code options before writing any of it. Terraform earns its keep with a cloud API and state worth tracking, and Multipass has neither a first-party provider nor state I care about. Ansible suits long-lived hosts patched in place, and these VMs are cattle: if one drifts, I delete it and rebuild it in six minutes. So cloud-init sets each node up once at boot, and a short shell script drives Multipass.

All five share one Multipass zone. Multipass gives each zone its own subnet, with the host routing between them. kube-vip's leader claims the API's virtual IP by answering ARP for it, and ARP only reaches machines on the same subnet. Spread the control planes across zones and the address can't move to a survivor when the leader fails.

When the first build took 18 minutes, I measured before changing anything. cloud-init's own timings put most of each node's 3m 20s in package downloads, and the server's connection tops out at 1.1 MB/s. Each VM fetched the same 169 MB, so five of them pulled 845 MB of identical bytes. Parallel launches would only have split that connection five ways. A cache fixes that: the first VM fetches, and the rest read from the host. A `registry.k8s.io` mirror does the same for the control-plane images, which kubeadm will pull on three nodes in [#11](https://github.com/guy-with-a-why/telemetry-blackbox/issues/11).

## What challenges were faced

containerd was the first surprise. Each node finds my registry through a small file under `certs.d`, which says that images named `localhost:5000` come from the host over plain HTTP. Ubuntu now ships containerd 2.2, where Kubernetes pulls go through a new transfer service that never reads that file. So every pull went to `https://localhost:5000` on the node itself and failed. Pulling the same image two ways narrowed it down. `ctr`, handed the file directly, worked. `crictl`, which pulls the way the kubelet does, didn't. Setting `use_local_image_pull = true` sends Kubernetes pulls back through the older path, which reads the file.

The apt cache took three attempts. Proxy mode refused the Kubernetes repository with a 403, because apt-cacher-ng reads the colons in `pkgs.k8s.io` paths as a port. Its shortcut paths failed in milliseconds with a 503. I traced its system calls and found it looking up a host called `ubuntu` in DNS. Putting the real host first in the path, as in `http://cache:3142/pkgs.k8s.io/core:/stable:/v1.36/deb/`, got past the 403 and the 503. The `kubectl` package then took 11.6 seconds through the cache the first time and 0.02 the second. The signing key still comes straight from upstream, so the cache can't swap it.

## What's next

[#11](https://github.com/guy-with-a-why/telemetry-blackbox/issues/11) is next: a highly available control plane, built by hand with kubeadm, kube-vip and Cilium. The virtual IP has to sit outside the range Multipass hands out, so that gets checked first.

The biggest risk is 1.5 GB per control plane. If one runs short of memory, I'll move memory from `data-1` before giving up a node. If that isn't enough, the fallback is one control plane on a VM and the HA drills on kind.
