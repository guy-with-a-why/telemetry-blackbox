# Engine start: a control plane built by hand

*15 November 2026*

## What was done

I bootstrapped the cluster this afternoon. It's a Sunday, so it came out of the time in hand. I typed every kubeadm command myself on my home server, because that's the point of [#11](https://github.com/guy-with-a-why/telemetry-blackbox/issues/11). Forty-seven minutes after `kubeadm init` on cp-1, `just cluster-check` came back clean. Three control planes answer behind one virtual IP, `10.97.0.250`, two workers have joined and Cilium carries the pod network.

![My home server, an i5-3320M with two cores, four threads and 16 GB, runs five Multipass VMs on QEMU. cp-1, cp-2 and cp-3 each have 2 vCPUs and 1.5 GB, and run static Pods for etcd, the API server, the scheduler, the controller manager and kube-vip, plus the kube-proxy, cilium and cilium-envoy DaemonSets. cp-1 also runs both CoreDNS Pods, and cp-3 holds 10.97.0.250 and the etcd leader. edge-1 has 2 GB and data-1 4 GB, and each runs the DaemonSets and one cilium-operator. Ten vCPUs share four threads on the zone1 bridge.](../diagrams/host-to-pods.svg)

A kubeadm bootstrap starts like an airliner's engines. They come on one at a time in a fixed order, and the first runs on ground power. The cluster even keeps a record of it. Every Pod's age counts from when it started, so reading the `AGE` column oldest first replays the afternoon. cp-1 came up at 12:53, cp-3 joined eight minutes later, then cp-2, then both workers. Cilium went on about fifteen minutes in.

This is how things looked a minute or two after that. The control plane was running on all three nodes, but every node was NotReady and CoreDNS was stuck in Pending. That's expected. A node only reports Ready once a network plugin has written its config to `/etc/cni/net.d`, and Cilium writes that file when its agent starts. The agents were still waiting for their images.

![kubectl get pods in kube-system at T+17. etcd, kube-apiserver, kube-controller-manager, kube-scheduler and kube-vip run on cp-1, cp-2 and cp-3. kube-proxy runs on five nodes. The Cilium agents sit at Init:0/6, the Cilium envoy and operator Pods are ContainerCreating and both CoreDNS Pods are Pending.](assets/2026-11-15-bootstrap-pods.gif)

The ages show more than the order. `kube-vip-cp-1` is a minute younger than `etcd-cp-1`, because the one edit I made after init restarted it. On cp-3, kube-vip is younger than everything else on the node, because a node has no `admin.conf` until it has joined. A couple of hours later, all 34 Pods in `kube-system` were Running. The restarts on cp-1 are a story for further down.

![k9s showing all 34 Pods in kube-system a couple of hours later, Running across cp-1, cp-2, cp-3, edge-1 and data-1. On cp-1, the controller manager, the scheduler and kube-vip show one restart each, and three Cilium agents show one restart. The API server on cp-2 is younger than its neighbours.](assets/2026-11-15-k9s.gif)

## Why was it done that way

kube-vip is the first engine, and it needs ground power. `kubeadm init` reaches the API through the virtual IP, so kube-vip has to hold that address while init runs. It claims the address by taking a Lease from the API server, and that needs credentials. Since Kubernetes 1.29, `admin.conf` gets its rights from a binding that init only creates once the API server is up. So on cp-1, kube-vip starts on `super-admin.conf`, which is in the `system:masters` group and skips [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#user-facing-roles) entirely. When init finishes, I point kube-vip back at `admin.conf` and the cart comes off. The [kube-vip docs](https://kube-vip.io/docs/installation/static/) cover the step.

![kube-vip on cp-1 in five steps. Before init it borrows super-admin.conf, which skips RBAC. Init starts the API server, and kube-vip takes the Lease and the virtual IP. Init binds kubeadm:cluster-admins, so admin.conf works. One edit points kube-vip at admin.conf and disconnects super-admin.conf. cluster-check now fails if any kube-vip still reads super-admin.conf.](../diagrams/ground-power.svg)

Forgetting that last step would be easy, and nothing would tell me. kube-vip would carry on working with rights no binding grants and none can take away. That's why `cluster-check` now looks for it. `super-admin.conf` lives only on cp-1, readable by root, and nothing runs on it now.

The whole control plane runs as [static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/), kube-vip included. A Deployment needs the API server to accept it, etcd to store it, the controller manager to create its Pods and the scheduler to place them. Those four are the control plane, so they can't start that way. Instead, the kubelet runs whatever manifests sit in `/etc/kubernetes/manifests`, with no API involved, and keeps them running if the API goes down.

What `kubectl` shows for a static Pod is a mirror Pod, a read-only copy the kubelet posts to the API. Deleting it changes nothing on the node. I tried it on cp-2. The API server's Pod came straight back with an age of nine seconds, the same container underneath and the node itself, `Node/cp-2`, as its owner. To change a static Pod, I edit its file, which is exactly what switching kube-vip to `admin.conf` was.

![Deleting the mirror Pod kube-apiserver-cp-2. Before, the Pod is 39 minutes old and crictl on cp-2 shows container b34bcdeb. After the delete, the Pod is back at 9 seconds old and crictl shows the same container. The Pod's owner is Node cp-2.](assets/2026-11-15-static-pods.gif)

kubeadm also wrote the cluster's trust into `/etc/kubernetes/pki`. There are three certificate authorities, each good for ten years, and leaf certificates that last a year. The main one, `ca`, signs for the API server, the other components and both admin kubeconfigs. etcd gets its own authority because it holds everything. Apart from etcd's own members, only the API server and the health check carry a certificate etcd accepts. A leaked kubelet certificate would cost me a node and nothing more. The third authority covers the API server when it hands requests on to extension APIs, and `sa.key` signs the tokens ServiceAccounts carry. The [PKI reference](https://kubernetes.io/docs/setup/best-practices/certificates/) lists every file.

![The PKI in /etc/kubernetes/pki. The ca authority signs the API server's serving certificate, its kubelet client certificate, admin.conf, super-admin.conf and each component's kubeconfig. etcd-ca signs etcd's server and peer certificates, the API server's etcd client certificate and the health-check client. front-proxy-ca signs the front-proxy client. sa.key and sa.pub are not an authority and sign ServiceAccount tokens. Every leaf certificate lasts a year.](../diagrams/pki.svg)

Mine expire on 15 November 2027. `kubeadm upgrade` [renews the control plane's certificates](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/#automatic-certificate-renewal) as it goes, and kubelets rotate their own, so a cluster upgraded once a year never sees one lapse.

etcd is [stacked](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/#stacked-etcd-topology), one member on each control plane. External etcd would keep its failures apart from the control plane, but it needs three more VMs on a 16 GB box. Stacked ties each member to its control plane, and [#12](https://github.com/guy-with-a-why/telemetry-blackbox/issues/12) will test what that costs. I went with stacked. Each API server talks only to its own member, on `127.0.0.1:2379`, and the members agree through [Raft](https://raft.github.io/), which counts a write once a majority has it.

![Stacked etcd. Each control plane's API server talks only to its own etcd member on 127.0.0.1:2379. The cp-3 member is the leader and replicates to cp-1 and cp-2 over Raft on port 2380. A write commits once two of the three members have it.](../diagrams/stacked-etcd.svg)

Three is the smallest cluster that survives a failure. With two of three up, there's still a majority, so writes carry on. Any two majorities share a member, so a new leader always has every committed write. A fourth member adds a vote but no tolerance, because the majority grows to three. Two members are worse than one. Either failure stops writes, and there's twice the hardware to fail. The [etcd FAQ](https://etcd.io/docs/v3.6/faq/#why-an-odd-number-of-cluster-members) has the arithmetic.

One call of my own sits under the pod network. Cilium's default pod range, `10.0.0.0/8`, covers the bridge the VMs live on. I could have given Cilium a range of its own, but then the pod range would live in two places. So Cilium takes each node's range from Kubernetes, and `10.244.0.0/16` is set once, in `kubeadm.yaml`.

## What challenges were faced

Before starting the failover drill, I read back through `deploy/` and wasn't sure kube-vip was set up properly. The manifest turned out to be fine. It matches what kube-vip v1.3.1 generates itself, apart from two settings that only matter when the address comes from DHCP or DNS. The real problem was simpler. There was no cluster to fail over. [#11](https://github.com/guy-with-a-why/telemetry-blackbox/issues/11) had closed itself when [#84](https://github.com/guy-with-a-why/telemetry-blackbox/pull/84) merged the evening before, with every box unticked, and the VMs had been rebuilt that evening without kubeadm ever running. I'd linked the PR in GitHub's Development panel, and that closes an issue on merge, whatever the description says. I reopened it. Now I reference issues only in a pull request's description, and I check that a pull request closes nothing it shouldn't before it merges.

Going through the checks turned up a gap in my own proof. `cluster-check` confirmed one kube-vip held the address and never asked about the other two. A crashlooping standby would have passed, then failed the drill that matters. Nothing checked that cp-1 had come off `super-admin.conf` either. [#100](https://github.com/guy-with-a-why/telemetry-blackbox/pull/100) now fails unless all three run kube-vip on `admin.conf`. It also fixes how I found kube-vip's network interface. I took the third field of `ip route get` for the virtual IP, but on the node holding that IP the answer starts `local 10.97.0.250 dev lo`, and the third field is the word `dev`.

Cilium was slow to start. All five nodes pulled the same images through a quay.io mirror that had never seen them, on a line that tops out near 1 MB/s, and the agents waited over twenty minutes. The mirror pays off on the next rebuild.

The interesting bit came as Cilium finished. Three of its agents exited once as they started, and my home server was flat out. A few minutes later its load average read 10 on four threads. cp-1 stopped keeping up, and within twenty seconds it lost every leadership it held. etcd went first, at 13:36:37, when cp-3 won an election. Then kube-vip's [Lease](https://kubernetes.io/docs/concepts/architecture/leases/) went, then the controller manager's and the scheduler's. Each of those three stood down by exiting, and the kubelet started it again as a standby. Those are cp-1's restarts in k9s.

kube-vip's logs show the odd part. cp-3 took the address at 13:36:49, but cp-1 was so starved it only noticed its renewal had failed three seconds later. It then spent twelve seconds trying to hand the Lease back through its own slow API server, and only dropped the address at 13:37:09. For twenty seconds, two nodes answered for the same IP. The cluster came through it, and #12 now has a failover from the wild to measure itself against.

## What's next

[#12](https://github.com/guy-with-a-why/telemetry-blackbox/issues/12) takes the control planes down on purpose, one and then two. With one down, etcd keeps its majority, and if that node held the address, kube-vip should move it within about fifteen seconds. With two down, writes stop. Every kube-vip renews its Lease through its own API server, so I expect the address to vanish, while Pods already on the workers keep serving. [#13](https://github.com/guy-with-a-why/telemetry-blackbox/issues/13) follows with an etcd snapshot and restore. That leaves #12 to #17 for the five evenings to Friday.

The biggest risk is CPU. My home server is a 2012 laptop with an i5-3320M, battery still at 91%. At idle, with nothing of mine on it yet, the VMs hold it at about half its CPU. The three control planes take about 11% each and the workers around 5%. Memory comes second, with 4 GB free and 575 MiB already in swap. Redpanda and ClickHouse will want their share of both.

![btop on my home server at idle. The i5-3320M's four threads each sit near 50%, with a load average around 3.6. Five qemu-system-x86 processes lead the list, three with 1.5 GB, one with 2 GB and one with 3.9 GB. Memory is 73% used and 575 MiB of swap is in use.](assets/2026-11-15-btop.gif)

A longer Lease would make false alarms rarer, but it wouldn't stop a starved node holding on to the address late. A bigger CPU share for the control-plane VMs would, so a busy `data-1` can't starve them. I'll measure both in #12 and keep whichever the numbers back.

#11 closed this afternoon with every box ticked.

## Quiz

Nine questions on the post, for anyone who wants to check it's landed. Open one for my answer.

<details>
<summary>You delete <code>kube-apiserver-cp-2</code> with kubectl. What happens on the node?</summary>

Nothing. I only deleted the mirror, the kubelet put it straight back and the container never stopped.

</details>

<details>
<summary>Why can't the control plane run as a Deployment?</summary>

A Deployment needs the API server, etcd, the scheduler and the controller manager to exist first. Those are the control plane, so the kubelet starts them from files on disk.

</details>

<details>
<summary>Why was every node NotReady until Cilium started?</summary>

The kubelet only reports Ready once a network plugin has written its config to `/etc/cni/net.d`. Cilium writes it when its agent starts.

</details>

<details>
<summary>Why does kube-vip start on <code>super-admin.conf</code>, and why move it off?</summary>

It has to take its Lease before `admin.conf` has any rights. `super-admin.conf` skips RBAC and nothing can revoke it, so it only stays until init finishes.

</details>

<details>
<summary>Why does etcd have its own certificate authority?</summary>

So a certificate from the main authority can't open the database. Only the API server and the health check hold one that etcd accepts.

</details>

<details>
<summary>The certificates last a year. What keeps them from expiring?</summary>

`kubeadm upgrade` renews the control plane's as it goes, and kubelets rotate their own. Upgrade at least once a year and nothing lapses.

</details>

<details>
<summary>Why run three etcd members and not four?</summary>

Three survives one failure. Four still only survives one, because the majority grows to three, and there's more hardware to fail.

</details>

<details>
<summary>Two control planes go down. What happens to the virtual IP?</summary>

I expect it to vanish. Each kube-vip renews its Lease through its own API server, and without quorum nothing can renew it. #12 will tell me if I'm right.

</details>

<details>
<summary>cp-3 took the address at 13:36:49. Why could cp-1 still answer for it?</summary>

cp-1 was too starved to notice it had lost the Lease, then spent twelve seconds trying to hand it back through its own slow API server. Only then did it drop the address.

</details>
