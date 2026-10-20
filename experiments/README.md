# Experiments

Reproducible failure and load tests. The methodology is described in section 7 of
[`docs/paper.md`](../docs/paper.md). Raw output goes to `results/`, which is git-ignored. Only
summaries are published.

| ID | Script | Question |
|---|---|---|
| E1 | `chaos/es-node-failure.sh` | How long until the cluster is writable and green again after losing a node? |
| E2 | `chaos/gateway-failover.sh` | How long does OTLP ingestion stay down when the active gateway dies? |
| E3 | `k6/load.js` | What is the latency and resource cost under sustained load, with and without instrumentation? |
| E4 | E2 + Kibana | Is telemetry lost during a gateway outage? (Count spans generated vs. stored.) |

## Requirements

`bash`, `curl`, `jq`, `bc`, `k6`, SSH access to the VMs/hypervisors, and the lab CA at `ansible/.pki/ca.crt`.

```bash
export ELASTIC_PASSWORD=...        # never commit it
export ES_URL=https://es-01.lab.example:9200

./chaos/es-node-failure.sh <hypervisor-host> <vmid-of-es-02>
./chaos/gateway-failover.sh
BASE_URL=http://apps-01.lab.example:8080 k6 run k6/load.js
```
