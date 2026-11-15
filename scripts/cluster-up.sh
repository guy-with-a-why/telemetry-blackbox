#!/usr/bin/env bash
# Bootstraps the cluster on the VMs that `just vms` built. It runs steps 1 to 8
# of docs/runbooks/bootstrap.md, each marked below, so the runbook explains
# every line. It's safe to run again: a control plane that has initialised or
# a node that has joined is left alone, and a half-finished one stops the
# script with the runbook's fix.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

first=${control_planes[0]}
others=("${control_planes[@]:1}")
kubeconfig=$HOME/.kube/blackbox.conf

if ! command -v helm >/dev/null; then
  echo "helm is missing; run mise install" >&2
  exit 1
fi

has() { multipass exec "$1" -- sudo test -e "$2"; }

# kubectl on cp-1 through its own API server, whose certificate names 127.0.0.1.
first_kubectl() {
  multipass exec "$first" -- sudo kubectl --kubeconfig /etc/kubernetes/admin.conf \
    --server https://127.0.0.1:6443 "$@"
}

# True once cp-1's API server, and so its etcd, passes /readyz.
api_ready() { first_kubectl get --raw /readyz >/dev/null 2>&1; }

# Points cp-1's kube-vip at another kubeconfig. Only the hostPath line
# matches, because mountPath has a capital P.
kube_vip_reads() {
  multipass exec "$first" -- sudo sed -i "s#path: /etc/kubernetes/$1#path: /etc/kubernetes/$2#" \
    /etc/kubernetes/manifests/kube-vip.yaml
}

# A control plane has joined once kubeadm has labelled it, the last step of
# its join. A worker has joined once it has kubelet.conf.
joined() {
  if [[ $1 == cp-* ]]; then
    [[ -n $(first_kubectl get nodes --field-selector "metadata.name=$1" \
      -l node-role.kubernetes.io/control-plane -o name 2>/dev/null) ]]
  else
    has "$1" /etc/kubernetes/kubelet.conf
  fi
}

join() { multipass exec "$1" -- sudo kubeadm join --config "$cluster_dir/join.yaml"; }

# Fresh secrets on every run, never written to the repo. cluster-files.sh
# fills them in.
BOOTSTRAP_TOKEN=$(multipass exec "$first" -- kubeadm token generate)
CERTIFICATE_KEY=$(multipass exec "$first" -- kubeadm certs certificate-key)
export BOOTSTRAP_TOKEN CERTIFICATE_KEY

# Step 1. Write the files.
scripts/cluster-files.sh init

if api_ready; then
  echo "$first: initialised already"
  just_initialised=false
elif has "$first" /etc/kubernetes/admin.conf; then
  # A slow cp-1 isn't a broken one, so a reset is only safe before any join.
  for name in "${others[@]}"; do
    if has "$name" /etc/kubernetes/kubelet.conf; then
      echo "$first: its API isn't ready. Wait, or run just cluster-check" >&2
      exit 1
    fi
  done
  echo "$first: its API isn't ready. Wait, or if init stopped halfway, run 'sudo kubeadm reset -f' on $first and start again" >&2
  exit 1
else
  # Step 2. kube-vip holds the VIP through init on super-admin.conf, because
  # admin.conf has no rights until init finishes.
  multipass exec "$first" -- sudo cp "$cluster_dir/kube-vip.yaml" /etc/kubernetes/manifests/
  kube_vip_reads admin.conf super-admin.conf

  # Step 3. Initialise the first control plane. The token and the key come
  # from kubeadm.yaml.
  multipass exec "$first" -- sudo kubeadm init --config "$cluster_dir/kubeadm.yaml" --upload-certs
  just_initialised=true
fi

# Step 4. super-admin.conf skips RBAC, so nothing runs on it after init. Every
# run does this, in case an earlier one stopped straight after init.
kube_vip_reads super-admin.conf admin.conf

# Before steps 5 and 6: find the nodes still to join and write their files.
# A node with kubelet.conf that fails the joined check stopped halfway.
declare -A pending=()
for name in "${others[@]}" "${workers[@]}"; do
  if joined "$name"; then
    echo "$name: joined already"
  elif has "$name" /etc/kubernetes/kubelet.conf; then
    echo "$name: a join stopped halfway. See 'A join failed halfway' in docs/runbooks/bootstrap.md" >&2
    exit 1
  else
    pending[$name]=1
  fi
done

if ((${#pending[@]} > 0)); then
  # Init's token may have expired and its certificates go after two hours, so upload this run's.
  if [[ $just_initialised == false ]]; then
    multipass exec "$first" -- sudo kubeadm token create "$BOOTSTRAP_TOKEN" >/dev/null
    multipass exec "$first" -- sudo kubeadm init phase upload-certs --upload-certs \
      --certificate-key "$CERTIFICATE_KEY" >/dev/null
  fi
  scripts/cluster-files.sh join
fi

# Step 5. Join cp-2 and cp-3, one at a time, because etcd adds one member at a
# time. kube-vip goes in after the join, because the node has no admin.conf
# before it.
for name in "${others[@]}"; do
  if [[ -v pending[$name] ]]; then join "$name"; fi
  if ! has "$name" /etc/kubernetes/manifests/kube-vip.yaml; then
    multipass exec "$name" -- sudo cp "$cluster_dir/kube-vip.yaml" /etc/kubernetes/manifests/
  fi
done

# Step 6. Join the workers.
for name in "${workers[@]}"; do
  if [[ -v pending[$name] ]]; then join "$name"; fi
done

# Step 7. Copy the kubeconfig here, where the bridge reaches the VIP directly.
# Via a variable, because multipass exec spins at 99% CPU when stdout is a file.
mkdir -p "$(dirname "$kubeconfig")"
config=$(multipass exec "$first" -- sudo cat /etc/kubernetes/admin.conf)
(umask 077 && printf '%s\n' "$config" >"$kubeconfig")
echo "kubeconfig: $kubeconfig"

# Step 8. Install Cilium, or leave it as it is if nothing changed. On a cold
# mirror the images take over twenty minutes.
helm upgrade --install cilium cilium --repo https://helm.cilium.io \
  --version "$cilium_version" --namespace kube-system \
  --values deploy/cluster/cilium-values.yaml \
  --kubeconfig "$kubeconfig" --wait --timeout 30m
