# 0006. A scripted kubeadm bootstrap over Terraform or Ansible

- **Status:** Proposed
- **Date:** 2026-11-15
- **Issue:** #105

## Context

I bootstrapped the cluster by hand for #11, following
[the bootstrap runbook](../runbooks/bootstrap.md). It took 47 minutes from
`kubeadm init` to a passing `just cluster-check`. Doing it once by hand was
the point. Doing it every time isn't.

The drills that follow break the cluster on purpose. #12 stops two control
planes, #13 restores etcd from a snapshot and the 1.36 to 1.37 upgrade can fail
halfway. Any of them can end in a rebuild, and a missed step by hand, such as
kube-vip left on `super-admin.conf`, costs an evening.

Part of the path is already scripted:

1. `just host` runs the registry, the image mirrors and the apt cache.
2. `just vms` builds the five VMs from cloud-init and skips any that exist. A
   warm rebuild takes 6m09s.
3. `just cluster-files` renders the kubeadm and kube-vip files.
4. `just cluster-check` proves the result.

What's left is runbook steps 2 to 8. That's about ten commands across five
VMs, in order, passing a token, a certificate key and a CA hash from cp-1 to
the others. The machines already exist, so this is orchestration, not
provisioning.

The constraints:

- One server runs five Multipass VMs in one zone, because kube-vip's ARP mode
  needs one subnet.
- I reach the VMs with `multipass exec`, not SSH.
- Leg 1 is due on 20 November, and this has to land before #12.
- Every line of the automation has to map to a runbook step.

## Decision

- `just cluster-up` runs runbook steps 2 to 8 through `scripts/cluster-up.sh`
  over `multipass exec`. `just up` chains `vms`, `cluster-up` and
  `cluster-check` into a rebuild from nothing.
- kubeadm's own configuration carries the joins. `kubeadm.yaml` takes a
  bootstrap token and a certificate key, generated on each run and never
  committed. A `JoinConfiguration` per role replaces the join flags,
  `--ignore-preflight-errors=Mem` included. The script reads the CA hash after
  init, because the CA doesn't exist before it.
- Each step checks before it acts. Init is skipped if cp-1 has `admin.conf`,
  and a join is skipped if the node has `kubelet.conf`.
- The script copies `admin.conf` to the server and installs Cilium from there
  with Helm. `just kubeconfig` sets up my laptop's copy and the tunnel.
- The VMs stay on `vms.sh`. The upgrade and the drills stay manual.

## Options I turned down

- **Terraform or OpenTofu for the VMs.** Terraform earns its keep by
  reconciling state against an API. Here that's one server's Multipass,
  already driven by a script that skips what exists. The community provider
  documents no `--zone` option and was last updated in December 2025. Its
  state would also go stale whenever a drill has me delete a VM by hand.
- **Ansible.** It's agentless and the usual way to run kubeadm across
  machines. Here it needs SSH keys injected through cloud-init, an inventory
  that copies `deploy/vms/config.sh` and a Python toolchain, all for about ten
  commands.
- **Kubespray.** It builds exactly this cluster, kube-vip and Cilium included.
  It also hides every step I've just learned inside a large Ansible project,
  and debugging it means debugging that project.
- **kubeadm from cloud-init.** Each VM could init or join on first boot from
  shared secrets. The order between nodes would rest on retries, and a failed
  join would only show in that VM's cloud-init log.
- **Flux or Argo CD at bootstrap.** Both need a working pod network, so Cilium
  goes in directly either way. GitOps for the Leg 3 workloads is its own
  decision.
- **Staying manual.** Fine for one bootstrap. Not for a cluster I plan to
  break several times a week.

## Consequences

- A rebuild is one command and a wait, so the drills can be as destructive as
  they need to be.
- The runbook stays. It explains what the script does and why, and its
  recovery steps still apply when the script stops halfway.
- The script and the runbook can drift apart. Each step in the script names
  the runbook step it runs, and `cluster-check` proves the result either way.
- The token and certificate key sit in plain text in `~/cluster/` on the VMs.
  The token expires after 24 hours and the uploaded certificates after two.
  That's fine on a private bridge and wrong anywhere else.
- Helm has to be on the server. `mise.toml` already pins it.
- I'd revisit this if the cluster moved to real machines or a hypervisor with
  an API, such as Proxmox. Then Terraform for the machines and Ansible for
  kubeadm earn their place, or Cluster API once there's more than one cluster.

## References

- [kubeadm configuration (v1beta4)](https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/)
- [Creating highly available clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)
- [terraform-provider-multipass](https://github.com/larstobi/terraform-provider-multipass)
- [Multipass availability zones](https://canonical.com/multipass/docs/latest/tutorial/availability-zones/)
- [Kubespray](https://github.com/kubernetes-sigs/kubespray)
