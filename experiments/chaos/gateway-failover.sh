#!/usr/bin/env bash
# E2 - Stop the gateway that currently holds the VIP and measure how long
# OTLP ingestion through the VIP is unavailable.
#
# Env: VIP_IP, VIP_FQDN (default otel-gw.lab.example), GATEWAYS ("es-01 es-02 es-03"),
#      SSH_USER (default debian), CA_CERT (default ansible/.pki/ca.crt)
set -euo pipefail

VIP_IP="${VIP_IP:?set VIP_IP}"
VIP_FQDN="${VIP_FQDN:-otel-gw.lab.example}"
read -r -a GATEWAYS <<< "${GATEWAYS:-es-01 es-02 es-03}"
SSH_USER="${SSH_USER:-debian}"
CA_CERT="${CA_CERT:-$(dirname "$0")/../../ansible/.pki/ca.crt}"
OUT="$(dirname "$0")/../results/e2-$(date +%Y%m%d-%H%M%S).csv"
mkdir -p "$(dirname "$OUT")"

now() { date +%s.%N; }
probe() { # HTTP code of an empty OTLP/HTTP export through the VIP
  curl -s -o /dev/null -w '%{http_code}' --max-time 1 --cacert "$CA_CERT" \
    --resolve "${VIP_FQDN}:4318:${VIP_IP}" \
    -X POST -H 'Content-Type: application/json' -d '{}' \
    "https://${VIP_FQDN}:4318/v1/traces" || true
}

holder=""
for gw in "${GATEWAYS[@]}"; do
  if ssh "${SSH_USER}@${gw}" "ip -o -4 addr show | grep -qw '${VIP_IP}'"; then
    holder="$gw"
  fi
done
[[ -n "$holder" ]] || { echo "No gateway holds ${VIP_IP}"; exit 1; }
echo "VIP held by ${holder}; probe=$(probe)"

t_stop=$(now)
ssh "${SSH_USER}@${holder}" "sudo systemctl stop edot-gateway"

t_fail=""
while true; do
  code="$(probe)"
  if [[ "$code" != "200" && -z "$t_fail" ]]; then t_fail=$(now); fi
  if [[ "$code" == "200" && -n "$t_fail" ]]; then t_ok=$(now); break; fi
  # Failover was faster than our probe interval.
  if [[ "$code" == "200" && $(echo "$(now) - $t_stop > 10" | bc) -eq 1 ]]; then
    t_fail=$t_stop; t_ok=$t_stop; break
  fi
  sleep 0.2
done

outage=$(echo "$t_ok - $t_fail" | bc)
ssh "${SSH_USER}@${holder}" "sudo systemctl start edot-gateway"

echo "run,failed_gateway,outage_s" > "$OUT"
echo "$(date -Iseconds),${holder},${outage}" >> "$OUT"
echo "Ingestion outage through VIP: ${outage}s (saved to ${OUT})"
