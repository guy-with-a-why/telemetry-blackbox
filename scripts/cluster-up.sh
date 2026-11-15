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
workers=()
for name in "${node_names[@]}"; do
  if [[ " ${control_planes[*]} " != *" $name "* ]]; then workers+=("$name"); fi
done
# cluster-files.sh puts the files in the default user's ~/cluster/.
files=/home/ubuntu/cluster
kubeconfig=$HOME/.kube/blackbox.conf

if ! command -v helm >/dev/null; then
  echo "helm is missing; run mise install" >&2
  exit 1
fi

has() { multipass exec "$1" -- sudo test -e "$2"; }

# A node's own API server answers, including its etcd. The serving
# certificate names 127.0.0.1.
api_ready() {
  multipass exec "$1" -- sudo kubectl --kubeconfig /etc/kubernetes/admin.conf \
    --server https://127.0.0.1:6443 get --raw /readyz >/dev/null 2>&1
}

# Points cp-1's kube-vip at another kubeconfig. Only the hostPath line
# matches, because mountPath has a capital P.
kube_vip_reads() {
  multipass exec "$first" -- sudo sed -i "s#path: /etc/kubernetes/$1#path: /etc/kubernetes/$2#" \
    /etc/kubernetes/manifests/kube-vip.yaml
}

# A control plane has joined once kubeadm has written its etcd manifest, the
# last file a control-plane join writes. A worker has joined once it has
# kubelet.conf. Either with kubelet.conf and no more stopped halfway.
joined() {
  if [[ " ${control_planes[*]} " == *" $1 "* ]]; then
    has "$1" /etc/kubernetes/manifests/etcd.yaml
  else
    has "$1" /etc/kubernetes/kubelet.conf
  fi
}

# Fresh secrets on every run, never written to the repo. cluster-files.sh
# fills them in.
BOOTSTRAP_TOKEN=$(multipass exec "$first" -- kubeadm token generate)
CERTIFICATE_KEY=$(multipass exec "$first" -- kubeadm certs certificate-key)
export BOOTSTRAP_TOKEN CERTIFICATE_KEY

# Step 1. Write the files.
scripts/cluster-files.sh init

if api_ready "$first"; then
  echo "$first: initialised already"
  fresh=false
elif has "$first" /etc/kubernetes/admin.conf; then
  echo "$first: init ran but its API isn't ready. Wait, or run 'sudo kubeadm reset -f' on $first and start again" >&2
  exit 1
else
  # Step 2. kube-vip holds the VIP through init on super-admin.conf, because
  # admin.conf has no rights until init finishes.
  multipass exec "$first" -- sudo cp "$files/kube-vip.yaml" /etc/kubernetes/manifests/
  kube_vip_reads admin.conf super-admin.conf

  # Step 3. Initialise the first control plane. The token and the key come
  # from kubeadm.yaml.
  multipass exec "$first" -- sudo kubeadm init --config "$files/kubeadm.yaml" --upload-certs

  # Step 4. super-admin.conf skips RBAC, so nothing runs on it after init.
  kube_vip_reads super-admin.conf admin.conf
  fresh=true
fi

# Every node that still has to join, stopping on any that stopped halfway.
pending=()
for name in "${others[@]}" "${workers[@]}"; do
  if joined "$name"; then
    echo "$name: joined already"
  elif has "$name" /etc/kubernetes/kubelet.conf; then
    echo "$name: a join stopped halfway. See 'A join failed halfway' in docs/runbooks/bootstrap.md" >&2
    exit 1
  else
    pending+=("$name")
  fi
done

if ((${#pending[@]} > 0)); then
  # On a later run, init's token and certificates have expired or belong to
  # another run, so this run's go in place.
  if [[ $fresh == false ]]; then
    multipass exec "$first" -- sudo kubeadm token create "$BOOTSTRAP_TOKEN" >/dev/null
    multipass exec "$first" -- sudo kubeadm init phase upload-certs --upload-certs \
      --certificate-key "$CERTIFICATE_KEY" >/dev/null
  fi

  # The CA exists now, so its hash can go in the join files.
  CA_HASH=sha256:$(multipass exec "$first" -- bash -c \
    'openssl x509 -pubkey -noout -in /etc/kubernetes/pki/ca.crt | openssl pkey -pubin -outform der | sha256sum' |
    cut -d' ' -f1)
  export CA_HASH
  scripts/cluster-files.sh join
fi

# Step 5. Join cp-2 and cp-3, one at a time, because etcd adds one member at a
# time. kube-vip goes in after the join, because the node has no admin.conf
# before it.
for name in "${others[@]}"; do
  if [[ " ${pending[*]} " == *" $name "* ]]; then
    multipass exec "$name" -- sudo kubeadm join --config "$files/join.yaml"
  fi
  if ! has "$name" /etc/kubernetes/manifests/kube-vip.yaml; then
    multipass exec "$name" -- sudo cp "$files/kube-vip.yaml" /etc/kubernetes/manifests/
  fi
done

# Step 6. Join the workers.
for name in "${workers[@]}"; do
  if [[ " ${pending[*]} " == *" $name "* ]]; then
    multipass exec "$name" -- sudo kubeadm join --config "$files/join.yaml"
  fi
done

# Step 7. Copy the kubeconfig here. The server sits on the bridge, so it
# reaches the VIP directly. `just kubeconfig` does the same for a laptop.
# multipass exec spins forever when its output goes straight to a file, so
# read it into a variable first.
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
