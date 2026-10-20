# ADR-0005: Free (Basic) license only

- **Status:** Accepted
- **Date:** 2026-10-20

## Context

The lab must be reproducible by anyone at no cost, so it cannot depend on a paid Elastic
subscription. The checks below come from the official self-managed subscription matrix
(elastic.co/subscriptions, October 2026).

## Decision

Use only features included in **Basic**:

| Included in Basic (used) | Not in Basic (avoided or replaced) |
|---|---|
| ECK: Elasticsearch, Kibana, APM Server, Elastic Agent on Kubernetes | ECK autoscaling, Elastic Maps Server |
| OpenTelemetry intake, APM Server, APM / Logs / Metrics apps | **APM service maps** |
| TLS, RBAC, native and file-realm users | Audit logging, field/document-level security |
| ILM, data stream lifecycle, snapshot/restore, SLM | Searchable snapshots |
| Dashboards, Kibana alerting with *Index* / *Server log* connectors | **SLOs**, **email/Slack/webhook connectors**, ML anomaly detection |

The replacements (threshold rules for SLIs, ElastAlert2 for notifications) are listed in
[`kibana/README.md`](../../kibana/README.md).

## Consequences

- ✅ Zero licensing cost; anyone can reproduce the lab.
- ✅ Shows how far a production-like platform goes on the free tier.
- ❌ No error budgets or service maps out of the box.
- ❌ Elastic License 2.0 (not OSI open source): free to self-host, but not to offer as a managed service.
