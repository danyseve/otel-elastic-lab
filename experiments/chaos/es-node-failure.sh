#!/usr/bin/env bash
# E1 - Hard-stop one Elasticsearch VM and measure cluster recovery.
#
# Usage: es-node-failure.sh <hypervisor-host> <vmid>
# Env:   ES_URL (a node that is NOT being stopped), ELASTIC_PASSWORD,
#        CA_CERT (default: ansible/.pki/ca.crt), DOWNTIME (seconds, default 120)
set -euo pipefail

PVE_HOST="${1:?hypervisor host}"
VMID="${2:?vmid}"
ES_URL="${ES_URL:?set ES_URL to a surviving node}"
: "${ELASTIC_PASSWORD:?set ELASTIC_PASSWORD}"
CA_CERT="${CA_CERT:-$(dirname "$0")/../../ansible/.pki/ca.crt}"
DOWNTIME="${DOWNTIME:-120}"
OUT="$(dirname "$0")/../results/e1-$(date +%Y%m%d-%H%M%S).csv"
mkdir -p "$(dirname "$OUT")"

now() { date +%s.%N; }
status() {
  curl -s --max-time 2 --cacert "$CA_CERT" -u "elastic:${ELASTIC_PASSWORD}" \
    "${ES_URL}/_cluster/health" | jq -r '.status // "unreachable"' || echo unreachable
}
wait_for() { # $1 = regex of acceptable states
  until [[ "$(status)" =~ $1 ]]; do sleep 0.5; done
}

echo "Initial status: $(status)"
[[ "$(status)" == "green" ]] || { echo "Cluster must be green before the test"; exit 1; }

t_stop=$(now)
ssh "root@${PVE_HOST}" "qm stop ${VMID}"
echo "VM ${VMID} stopped (hard)."

wait_for '^(yellow|red)$'; t_degraded=$(now)
echo "Cluster degraded: $(status)"

sleep "$DOWNTIME"

t_start=$(now)
ssh "root@${PVE_HOST}" "qm start ${VMID}"
wait_for '^green$'; t_green=$(now)

detect=$(echo "$t_degraded - $t_stop" | bc)
recover=$(echo "$t_green - $t_start" | bc)

echo "run,vmid,detect_s,downtime_s,recover_to_green_s" > "$OUT"
echo "$(date -Iseconds),${VMID},${detect},${DOWNTIME},${recover}" >> "$OUT"

echo "Detection: ${detect}s | Recovery to green after restart: ${recover}s"
echo "Saved to ${OUT}"
