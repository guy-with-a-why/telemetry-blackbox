# Autostart: the whole cluster in one command

*15 November 2026*

## What was done

This afternoon I built the control plane by hand, and it took 47 minutes from `kubeadm init` to a clean check. This evening I made it one command. `just up` builds the five VMs, initialises cp-1, joins the other four nodes, installs Cilium and runs `cluster-check`. From nothing to a passing check took 20 minutes and 8 seconds, VMs included. Run it again on a healthy cluster and it skips every node in under a minute.

The engines still start in the same order, with cp-1 on ground power first. A jet's autostart runs the same sequence a crew would, and the crew only has to press the button. [#105](https://github.com/guy-with-a-why/telemetry-blackbox/issues/105) has the work and [ADR 6](../adr/0006-scripted-kubeadm-bootstrap.md) the reasoning.

## Why was it done that way

If a sequence of actions is repeated by hand, and often, the system should do it instead. The drills in [#12](https://github.com/guy-with-a-why/telemetry-blackbox/issues/12) and [#13](https://github.com/guy-with-a-why/telemetry-blackbox/issues/13) break the cluster on purpose, so I'll be rebuilding it several times a week.

Terraform is the usual way to stand up VMs, so I looked at it first. Its Multipass provider doesn't support zones, and kube-vip needs all five VMs in one zone so they share a subnet. Ansible would have meant SSH keys and an inventory that copies my config, all for about ten commands. So kubeadm's own config files carry the joins. The token and the certificate key are generated fresh on each run and set before init. The CA's hash can't be, because the CA doesn't exist until init creates it, so the script reads it straight after. Every step checks before it acts, which is what makes a second run harmless.

## What challenges were faced

The first full run hung at step 7, copying the kubeconfig off cp-1. `multipass exec` was writing straight into a file, and it sat at 99% CPU for twenty minutes without writing a byte. Every other call in the scripts reads the output into a variable first, so this one does too now. Rerunning on the half-built cluster finished the job and proved the skip path a little earlier than planned. Then I tore it all down and rebuilt it in one clean pass, so the 20 minutes is a single honest run.

## What's next

[#12](https://github.com/guy-with-a-why/telemetry-blackbox/issues/12) takes the control planes down, one and then two, and [#13](https://github.com/guy-with-a-why/telemetry-blackbox/issues/13) restores etcd from a snapshot. Either can now end in `just up` and twenty minutes.

Further out, what runs on the cluster should come from Git too. [#107](https://github.com/guy-with-a-why/telemetry-blackbox/issues/107) puts Flux in charge of Redpanda, ClickHouse, the gateway, Spate and Grafana when Leg 3 brings them, so a rebuild restores the workloads as well as the cluster. Flux over Argo CD, because it's a few small controllers and my workers have 2 GB and 4 GB. The risk is Flux undoing a drill's damage as fast as I cause it, so the drill runbooks will suspend it first.
