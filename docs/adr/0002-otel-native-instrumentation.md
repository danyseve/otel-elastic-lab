# ADR-0002: OpenTelemetry-native instrumentation and storage

- **Status:** Accepted
- **Date:** 2026-10-20

## Context

Classic APM agents tie the application code to one vendor's protocol and data model.

## Decision

- Applications use OpenTelemetry SDKs / auto-instrumentation only and export OTLP.
- The Elasticsearch exporter runs in `mapping.mode: otel`, so documents keep OTel semantic conventions.
- The Elastic-specific pieces (`elasticapm` processor/connector) live **only** in the gateway tier.

## Consequences

- ✅ Switching backend means changing the gateway exporters, not the apps.
- ✅ Skills and configs carry over to any OTel-compatible vendor.
- ❌ Some Kibana APM features rely on the EDOT gateway components. Plain `otelcol-contrib` alone gives a reduced APM UI.
