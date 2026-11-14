# The shape of the cluster, in one place. The scripts that build and check
# the VMs source this file.
# shellcheck shell=bash disable=SC2034 # used by the scripts that source it

release=24.04
kubernetes_minor=v1.36

# One zone keeps every node on one subnet, which kube-vip's ARP mode needs.
zone=zone1
bridge=mpqemubr$zone
registry_port=5000
apt_cache_port=3142

# name    vCPUs  memory  disk
nodes=(
  "cp-1     2      1536M   10G"
  "cp-2     2      1536M   10G"
  "cp-3     2      1536M   10G"
  "edge-1   2      2G      10G"
  "data-1   2      4G      40G"
)

node_names=()
for node in "${nodes[@]}"; do node_names+=("${node%% *}"); done
unset node
