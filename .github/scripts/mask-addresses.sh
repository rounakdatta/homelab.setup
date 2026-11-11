#!/usr/bin/env bash
# Hide every tailnet and node address, and the tailnet's name, from the rest of
# this job's log, error output included. The logs of this repository are
# public, and an address map is exactly what they must not show. Run it right
# after the job joins the tailnet (and again after fetching a kubeconfig, to
# cover node addresses). GitHub masks values registered with ::add-mask::;
# the command lines themselves are not printed.
set -uo pipefail
values() {
  if command -v tailscale >/dev/null 2>&1; then
    tailscale status --json 2>/dev/null | jq -r '
      (.MagicDNSSuffix // empty),
      ((.Self, (.Peer // {} | .[])) | ((.TailscaleIPs // [])[], (.DNSName // "" | rtrimstr(".")), ((.Addrs // [])[] | sub(":[0-9]+$"; ""))))'
  fi
  if command -v kubectl >/dev/null 2>&1 && [ -s "${HOME}/.kube/config" ]; then
    kubectl get nodes -o jsonpath='{range .items[*].status.addresses[*]}{.address}{"\n"}{end}' 2>/dev/null
  fi
}
n=0
while read -r v; do
  [ -n "$v" ] || continue
  echo "::add-mask::$v"
  n=$((n + 1))
done < <(values | sed 's/^\[//; s/\]$//' | sort -u)
echo "masked $n address(es) for the rest of this job"
