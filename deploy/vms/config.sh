# The shape of the cluster, in one place. The scripts that build and check
# the VMs source this file.
# shellcheck shell=bash disable=SC2034 # used by the scripts that source it

release=24.04
kubernetes_minor=v1.36

# One zone keeps every node on one subnet, which kube-vip's ARP mode needs.
zone=zone1
bridge=mpqemubr$zone
registry_port=5000
k8s_mirror_port=5001
quay_mirror_port=5002
ghcr_mirror_port=5003
dockerhub_mirror_port=5004
apt_cache_port=3142

# The API's virtual IP, which kube-vip moves between the control planes. The
# bridge's DHCP range covers the whole /24, so cluster-files.sh and
# cluster-check.sh fail if a VM ever leases it.
vip=10.97.0.250
# kubeadm's default Service range, 10.96.0.0/12, covers the bridge's 10.97.0.0/24,
# and so does Cilium's default pod range, 10.0.0.0/8. Neither may overlap it.
pod_subnet=10.244.0.0/16
service_subnet=10.96.0.0/16
kube_vip_image=ghcr.io/kube-vip/kube-vip:v1.3.1@sha256:1962f9daf226503f7e6b107f595cb28b7917fd2d0113957075e19a3e5a6c1e33
# The Lease the control planes' kube-vips compete for.
kube_vip_lease=plndr-cp-lock
# The Cilium chart scripts/cluster-up.sh installs.
cilium_version=1.20.4
# Where cluster-files.sh puts the rendered files on each VM. It's absolute,
# because an unquoted ~ would expand on the server, not the VM.
cluster_dir=/home/ubuntu/cluster

# name    vCPUs  memory  disk
nodes=(
  "cp-1     2      1536M   10G"
  "cp-2     2      1536M   10G"
  "cp-3     2      1536M   10G"
  "edge-1   2      2G      10G"
  "data-1   2      4G      40G"
)

node_names=()
control_planes=()
workers=()
for node in "${nodes[@]}"; do
  node_names+=("${node%% *}")
  if [[ $node == cp-* ]]; then control_planes+=("${node%% *}"); else workers+=("${node%% *}"); fi
done
unset node
