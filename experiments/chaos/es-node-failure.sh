#!/usr/bin/env bash
# E1 - Hard-stop one k3s node VM and measure how Elasticsearch (ECK) degrades and recovers.
#
# Usage: es-node-failure.sh <hypervisor-host> <vmid>
# Env:   KUBECONFIG (default: ansible/.kube/config), NAMESPACE (default: observability),
#        DOWNTIME (seconds the VM stays off, default 120),
#        STOP_CMD / START_CMD (default: Proxmox "qm stop/start <vmid>" over ssh as root)
# Values are expanded locally on purpose before being sent over ssh.
# shellcheck disable=SC2029
set -euo pipefail

HV_HOST="${1:?hypervisor host}"
VMID="${2:?vmid}"
export KUBECONFIG="${KUBECONFIG:-$(dirname "$0")/../../ansible/.kube/config}"
NAMESPACE="${NAMESPACE:-observability}"
DOWNTIME="${DOWNTIME:-120}"
STOP_CMD="${STOP_CMD:-qm stop ${VMID}}"
START_CMD="${START_CMD:-qm start ${VMID}}"
OUT="$(dirname "$0")/../results/e1-$(date +%Y%m%d-%H%M%S).csv"
mkdir -p "$(dirname "$OUT")"

now() { date +%s.%N; }
# ECK reports the cluster health on the Elasticsearch resource itself.
health() {
  kubectl -n "$NAMESPACE" get elasticsearch lab -o jsonpath='{.status.health}' 2>/dev/null || echo unknown
}
wait_for() { # $1 = regex of acceptable states
  until [[ "$(health)" =~ $1 ]]; do sleep 1; done
}

echo "Initial health: $(health)"
[[ "$(health)" == "green" ]] || { echo "Cluster must be green before the test"; exit 1; }

t_stop=$(now)
ssh "root@${HV_HOST}" "${STOP_CMD}"
echo "VM ${VMID} stopped (hard)."

wait_for '^(yellow|red|unknown)$'; t_degraded=$(now)
echo "Cluster degraded: $(health)"

sleep "$DOWNTIME"

t_start=$(now)
ssh "root@${HV_HOST}" "${START_CMD}"
wait_for '^green$'; t_green=$(now)

detect=$(echo "$t_degraded - $t_stop" | bc)
recover=$(echo "$t_green - $t_start" | bc)

echo "run,vmid,detect_s,downtime_s,recover_to_green_s" > "$OUT"
echo "$(date -Iseconds),${VMID},${detect},${DOWNTIME},${recover}" >> "$OUT"

echo "Detection: ${detect}s | Recovery to green after restart: ${recover}s"
echo "Saved to ${OUT}"
