# ADR-0003: Two-tier collectors managed by the OpenTelemetry Operator

- **Status:** Accepted (supersedes the keepalived/VRRP design of v0.1.0)
- **Date:** 2026-10-20

## Context

Sending telemetry from every source straight to Elasticsearch would spread credentials everywhere,
couple the sources to backend availability, and lose data during outages.

## Decision

Everything is deployed with the `opentelemetry-kube-stack` chart (OpenTelemetry Operator):

- **Agent tier:** a DaemonSet (one collector per node) for container logs, kubelet and host metrics,
  plus a single-replica collector for cluster state and Kubernetes events.
- **Gateway tier:** a Deployment of the EDOT Collector (2 replicas spread across nodes). It is the
  only component holding Elasticsearch credentials, and it builds the APM aggregates.
- **External sources** (the apps' hosts) run `otelcol-contrib` with a persistent disk queue and reach
  the gateway through a MetalLB `LoadBalancer` Service with TLS from the lab CA (cert-manager).

## Consequences

- ✅ No single point of failure: Kubernetes reschedules collectors, and the Service only routes to ready pods.
- ✅ Active/active gateways, with no VRRP and no hand-written health-check scripts.
- ✅ Apps only talk to `127.0.0.1`. ES credentials live in a single Secret.
- ❌ Tail-based sampling would need trace-aware routing (`loadbalancing` exporter) in front of the gateways.
