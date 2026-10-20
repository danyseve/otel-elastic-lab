# Experiments

Reproducible failure and load tests. The methodology is described in section 7 of
[`docs/paper.md`](../docs/paper.md). Raw output goes to `results/`, which is git-ignored. Only
summaries are published.

| ID | Script | Question |
|---|---|---|
| E1 | `chaos/es-node-failure.sh` | When a whole k3s node (VM) dies, how long until ECK reports the cluster degraded, and how long until it is green again? |
| E2 | `chaos/gateway-failover.sh` | When a gateway pod dies, is OTLP ingestion through the MetalLB IP interrupted at all? |
| E3 | `k6/load.js` | What is the latency and resource cost under sustained load, with and without instrumentation? |
| E4 | E1/E2 + Kibana | Is telemetry lost during a failure? (Count spans generated vs. stored.) |

## Requirements

`bash`, `kubectl`, `curl`, `bc`, `k6`, SSH access to the hypervisor hosts (E1), the kubeconfig
written by Ansible (`ansible/.kube/config`) and the lab CA:

```bash
export KUBECONFIG=ansible/.kube/config
kubectl -n cert-manager get secret lab-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/lab-ca.crt

./chaos/es-node-failure.sh <hypervisor-host> <vmid-of-k8s-02>
GATEWAY_IP=10.0.0.40 CA_CERT=/tmp/lab-ca.crt ./chaos/gateway-failover.sh
BASE_URL=http://apps-01.lab.example:8080 k6 run k6/load.js
```
