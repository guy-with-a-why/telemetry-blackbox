# 0002. kubeadm over k3s or Talos

- **Status:** Accepted
- **Date:** 2026-11-19
- **Issue:** #16

## Context

I want to understand Kubernetes on my own machines, including the parts that
break. That means certificates, static Pods, etcd membership and upgrades.
The cluster I pick has to show those parts rather than hide them.

The cluster also has to survive the drills. Three control planes share a
virtual IP, so the API stays up when one goes down
([#12](https://github.com/guy-with-a-why/telemetry-blackbox/issues/12)).
etcd has to come back from a snapshot
([#13](https://github.com/guy-with-a-why/telemetry-blackbox/issues/13)). The
upgrade from 1.36 to 1.37 has to work one node at a time
([#140](https://github.com/guy-with-a-why/telemetry-blackbox/issues/140)).

The constraints:

- Five Multipass VMs on my home server, running Ubuntu 24.04. Each control
  plane has 2 vCPUs and 1.5 GB.
- kube-vip in ARP mode, so every node sits on one subnet.
- Leg 1 is due on 20 November.
- Whatever I learn has to carry over to clusters other people run.

## Decision

- kubeadm builds the cluster on Kubernetes v1.36, with stacked etcd on three
  control planes. Its v1beta4 files are in
  [`deploy/cluster/`](https://github.com/guy-with-a-why/telemetry-blackbox/tree/main/deploy/cluster).
- kubeadm leaves the virtual IP and the CNI to me. kube-vip runs as a static
  Pod on each control plane and holds the API's virtual IP, and Cilium is the
  CNI, installed with Helm.
- I bootstrapped it by hand first, following
  [the bootstrap runbook](../runbooks/bootstrap.md).
  [ADR 6](0006-scripted-kubeadm-bootstrap.md) scripts the same steps.

## Options I turned down

- **k3s.** One binary, a smaller footprint and a datastore, CNI, ingress and
  load balancer in the box. The bundle is the problem. Certificates, etcd and
  the control plane's static Pods sit behind k3s's own packaging, so the
  drills would test k3s rather than upstream Kubernetes.
- **Talos.** An immutable OS with no shell, run through an API. `talosctl` does
  the bootstrap, the joins and the upgrades, so I'd never run the steps I set
  out to learn.
- **kind or minikube.** kind's nodes are containers on one kernel, so
  stopping a machine or moving an ARP virtual IP isn't real. minikube runs
  kubeadm for me, behind its own bootstrapper.
- **A managed service such as EKS or GKE.** The provider owns the control
  plane and etcd, so #12 and #13 can't run.

## Consequences

- I own what a managed service would. Certificates expire after a year unless
  an upgrade renews them. etcd needs backups, and
  [the etcd runbook](../runbooks/etcd.md) restores one. Upgrades go one minor
  version at a time.
- The drills exercise upstream components.
  [Losing a control plane](../runbooks/control-plane.md) and restoring etcd
  behave as they would on any kubeadm cluster.
- It costs more memory than k3s. Each control plane runs etcd, the API
  server, the scheduler and the controller manager on 1.5 GB, below kubeadm's
  1.7 GB preflight check, so init and the control-plane joins skip it. If a
  control plane swaps or is OOM-killed, memory moves from data-1.
  [The deploy notes](https://github.com/guy-with-a-why/telemetry-blackbox/blob/main/deploy/README.md#why-the-kubeadm-memory-check-is-skipped)
  have the reasoning.
- It's slower to build than k3s. The first bootstrap took 47 minutes by hand,
  in a leg due on 20 November.
- The bootstrap and its checks are bash I maintain, for the reasons in
  ADR 6.
- I'd revisit this once the Leg 4 drills pass. By then kubeadm has taught
  what it can, and
  [#131](https://github.com/guy-with-a-why/telemetry-blackbox/issues/131)
  decides whether the finished platform moves to Talos, OpenTofu and Flux
  ([#130](https://github.com/guy-with-a-why/telemetry-blackbox/issues/130)).

## References

- [Creating highly available clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)
- [kubeadm configuration (v1beta4)](https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/)
- [Certificate management with kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)
- [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
- [k3s architecture](https://docs.k3s.io/architecture)
- [Talos Linux](https://www.talos.dev/)
