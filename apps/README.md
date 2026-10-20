# Instrumenting the applications

Applications only ever talk to the **local agent** (`127.0.0.1:4317` gRPC / `4318` HTTP). The
agent adds host metadata, buffers to disk and forwards to the gateway tier, so the apps never need
TLS certificates or Elasticsearch credentials.

The `app_instrumentation` Ansible role injects the standard `OTEL_*` variables into each systemd
unit listed in `instrumented_services` (see `ansible/group_vars/apps/main.yml`). Language-specific
auto-instrumentation goes in `extra_env`.

## Per-language recipes (zero-code auto-instrumentation)

| Language | One-time setup | `extra_env` |
|---|---|---|
| **Java** | Download `opentelemetry-javaagent.jar` (or EDOT Java) to `/opt/otel/` | `JAVA_TOOL_OPTIONS: "-javaagent:/opt/otel/opentelemetry-javaagent.jar"` |
| **Node.js** | `npm i @opentelemetry/api @opentelemetry/auto-instrumentations-node` | `NODE_OPTIONS: "--require @opentelemetry/auto-instrumentations-node/register"` |
| **Python** | `pip install opentelemetry-distro opentelemetry-exporter-otlp && opentelemetry-bootstrap -a install` | Prefix `ExecStart` with `opentelemetry-instrument` |
| **.NET** | Run the OpenTelemetry .NET auto-instrumentation install script | `CORECLR_ENABLE_PROFILING=1`, plus the variables from `instrument.sh` |
| **Go** | Manual SDK (or eBPF auto-instrumentation) | — |

## What to add by hand (where the value is)

Auto-instrumentation gives you HTTP, DB and messaging spans for free. To make the dashboards worth
showing, add a few **business signals**:

- **Ascenda:** spans around key domain operations, plus counters for operations completed and failed.
- **BJJ app:** spans for the main user flows, such as class bookings, check-ins and belt/progress updates,
  with attributes like `bjj.class.type` (never personal data).
- **Logs:** use the OTel log bridge of your logging library so every log line carries `trace_id`/`span_id`.

> ⚠️ Do not put personal data (names, emails, members' health information) in span
> attributes or logs. Use IDs or hashes.

## Checklist per service

- [ ] `service.name`, `service.version` and `deployment.environment.name` are set
- [ ] Traces visible in Kibana → Observability → Applications
- [ ] Logs correlated with traces (click from span → logs)
- [ ] RED metrics (rate, errors, duration) on a dashboard
- [ ] An SLO defined (e.g. 99% of requests < 500 ms over 7 days)
