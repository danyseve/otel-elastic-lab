# Instrumenting the applications

Ascenda and the BJJ app run **outside the Kubernetes cluster**, on their own hosts. On each host,
applications only ever talk to the **local agent** (`127.0.0.1:4317` gRPC / `4318` HTTP). The agent
adds host metadata, buffers to disk and forwards everything over TLS to the in-cluster gateway
(MetalLB IP, `otel-gw.<domain>`). The apps never need certificates or Elasticsearch credentials.

## Wiring

| How the app runs | Where the `OTEL_*` variables go |
|---|---|
| **systemd unit** | Listed in `instrumented_services` (`ansible/group_vars/apps/main.yml`). The `app_instrumentation` role writes a drop-in. |
| **Docker Compose** | A `compose.override.yml` with the same variables. Use `network_mode: host`, or point the endpoint at the host gateway IP, because inside a container `127.0.0.1` is the container itself. |

Minimal set of variables:

```bash
OTEL_SERVICE_NAME=ascenda
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=lab,service.version=1.0.0
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=1.0
```

## Per-language recipes (zero-code auto-instrumentation)

| Language | One-time setup | Extra variable |
|---|---|---|
| **Java** | Download `opentelemetry-javaagent.jar` (or EDOT Java) | `JAVA_TOOL_OPTIONS="-javaagent:/opt/otel/opentelemetry-javaagent.jar"` |
| **Node.js** | `npm i @opentelemetry/api @opentelemetry/auto-instrumentations-node` | `NODE_OPTIONS="--require @opentelemetry/auto-instrumentations-node/register"` |
| **Python** | `pip install opentelemetry-distro opentelemetry-exporter-otlp && opentelemetry-bootstrap -a install` | Prefix the command with `opentelemetry-instrument` |
| **.NET** | Run the OpenTelemetry .NET auto-instrumentation install script | `CORECLR_ENABLE_PROFILING=1` plus the variables from `instrument.sh` |
| **Go** | Manual SDK (or eBPF auto-instrumentation) | — |

## What to add by hand (where the value is)

Auto-instrumentation gives you HTTP, DB and messaging spans for free. To make the dashboards worth
showing, add a few **business signals**:

- **Ascenda:** spans around key domain operations, plus counters for operations completed and failed.
- **BJJ app:** spans for the main user flows (class bookings, check-ins, belt/progress updates),
  with attributes like `bjj.class.type` (never personal data).
- **Logs:** use the OTel log bridge of your logging library so every log line carries `trace_id`/`span_id`.

> ⚠️ Do not put personal data (names, emails, members' health information) in span
> attributes or logs. Use IDs or hashes.

## Checklist per service

- [ ] `service.name`, `service.version` and `deployment.environment.name` are set
- [ ] Traces visible in Kibana → Observability → APM
- [ ] Logs correlated with traces (click from span → logs)
- [ ] RED metrics (rate, errors, duration) on a dashboard
- [ ] An SLI threshold rule (e.g. error ratio > 1 % or p95 > 500 ms over 5 min), see [`kibana/`](../kibana/README.md)
