# ADR-0003: Two-tier collectors (agent + gateway) with a VRRP VIP

- **Status:** Accepted
- **Date:** 2026-10-20

## Context

Sending telemetry from every app straight to Elasticsearch would spread credentials everywhere,
couple the apps to backend availability, and lose data during outages.

## Decision

- An **agent** (`otelcol-contrib`) on every VM collects local signals and buffers to disk
  (`file_storage` + infinite retry).
- Three **gateways** (EDOT Collector), one on each ES node, terminate TLS, hold the credentials and write to ES.
- A **keepalived VIP**, health-checked against the collector's `health_check` extension, fronts the gateways.
- Agents on gateway hosts send to their local gateway. Remote agents use the VIP.

## Consequences

- ✅ No single point of failure in the ingestion path.
- ✅ Apps only talk to `127.0.0.1`. Secrets live in three places only.
- ❌ All remote traffic goes to one active gateway (active/passive). If volume grows, replace the VIP
  with the `loadbalancing` exporter, which also enables tail sampling.
