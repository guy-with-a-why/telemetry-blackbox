#!/usr/bin/env bash
# Usage: kubeconfig.sh <home-server>
# Runs on my laptop. Copies cp-1's admin.conf to ~/.kube/blackbox.conf,
# pointed at 127.0.0.1, and opens an SSH tunnel from there to the VIP on the
# server. The API server's certificate names 127.0.0.1 for this.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=deploy/vms/config.sh
source deploy/vms/config.sh

server=${1:?usage: $0 <home-server>}
kubeconfig=$HOME/.kube/blackbox.conf

mkdir -p "$(dirname "$kubeconfig")"
config=$(ssh "$server" multipass exec "${control_planes[0]}" -- sudo cat /etc/kubernetes/admin.conf)
if ! grep -qF "server: https://$vip:6443" <<<"$config"; then
  echo "admin.conf doesn't point at the VIP $vip" >&2
  exit 1
fi
(umask 077 && printf '%s\n' "${config//server: https:\/\/$vip:6443/server: https:\/\/127.0.0.1:6443}" >"$kubeconfig")
echo "kubeconfig: $kubeconfig"

# Open the tunnel unless something already listens on 6443.
if (exec 3<>/dev/tcp/127.0.0.1/6443) 2>/dev/null; then
  echo "tunnel: 127.0.0.1:6443 is open already"
else
  ssh -fN -o ExitOnForwardFailure=yes -L "6443:$vip:6443" "$server"
  echo "tunnel: 127.0.0.1:6443 to $vip"
fi
echo "export KUBECONFIG=$kubeconfig"
