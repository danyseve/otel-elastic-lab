#!/usr/bin/env bash
# E2 - Delete one OTel gateway pod and measure whether OTLP ingestion through the
# MetalLB IP is interrupted, and how long until the Deployment is back to full size.
#
# Env: GATEWAY_IP (MetalLB IP of otel-gateway-external), GATEWAY_FQDN (default otel-gw.lab.example),
#      CA_CERT (lab CA file), KUBECONFIG (default ansible/.kube/config), NAMESPACE (default observability)
set -euo pipefail

GATEWAY_IP="${GATEWAY_IP:?set GATEWAY_IP}"
GATEWAY_FQDN="${GATEWAY_FQDN:-otel-gw.lab.example}"
CA_CERT="${CA_CERT:?set CA_CERT to the lab CA file}"
export KUBECONFIG="${KUBECONFIG:-$(dirname "$0")/../../ansible/.kube/config}"
NAMESPACE="${NAMESPACE:-observability}"
SELECTOR="app.kubernetes.io/name=otel-gateway-collector"
OUT="$(dirname "$0")/../results/e2-$(date +%Y%m%d-%H%M%S).csv"
mkdir -p "$(dirname "$OUT")"

now() { date +%s.%N; }
probe() { # HTTP code of an empty OTLP/HTTP export through the external Service
  curl -s -o /dev/null -w '%{http_code}' --max-time 1 --cacert "$CA_CERT" \
    --resolve "${GATEWAY_FQDN}:4318:${GATEWAY_IP}" \
    -X POST -H 'Content-Type: application/json' -d '{}' \
    "https://${GATEWAY_FQDN}:4318/v1/traces" || true
}
ready_replicas() {
  kubectl -n "$NAMESPACE" get deploy otel-gateway-collector -o jsonpath='{.status.readyReplicas}'
}

want="$(kubectl -n "$NAMESPACE" get deploy otel-gateway-collector -o jsonpath='{.spec.replicas}')"
[[ "$(probe)" == "200" ]] || { echo "Gateway not answering before the test"; exit 1; }
victim="$(kubectl -n "$NAMESPACE" get pod -l "$SELECTOR" -o jsonpath='{.items[0].metadata.name}')"
echo "Deleting ${victim} (${want} replicas expected)"

t0=$(now)
kubectl -n "$NAMESPACE" delete pod "$victim" --grace-period=0 --force >/dev/null 2>&1 &

failed=0
while [[ "$(ready_replicas)" != "$want" || $(echo "$(now) - $t0 < 5" | bc) -eq 1 ]]; do
  [[ "$(probe)" == "200" ]] || failed=$((failed + 1))
  sleep 0.2
done
t_full=$(now)

restore=$(echo "$t_full - $t0" | bc)
echo "run,victim,failed_probes,time_to_full_replicas_s" > "$OUT"
echo "$(date -Iseconds),${victim},${failed},${restore}" >> "$OUT"
echo "Failed probes during the test: ${failed} | back to ${want} replicas in ${restore}s (saved to ${OUT})"
