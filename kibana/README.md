# Kibana assets

Exported dashboards and alert rules live here, so the lab can be restored without any clicking.

- `dashboards/*.ndjson`: export from *Stack Management → Saved objects*, import with
  `POST /api/saved_objects/_import`.
- Planned: manage dashboards and rules as code with the
  [`elastic/elasticstack`](https://registry.terraform.io/providers/elastic/elasticstack/latest)
  Terraform provider.

## Free (Basic) license: what we use and what we replace

| Need | Paid feature (Platinum+) | What this lab uses instead (free) |
|---|---|---|
| SLOs and error budgets | Kibana SLOs | Threshold / ES query rules on the error ratio and p95 latency, plus an SLI dashboard |
| Notifications (email, Slack, webhook) | Kibana connectors | Rules write to an *Index* connector; [ElastAlert2](https://github.com/jertel/elastalert2) (open source) sends the notifications |
| Service dependency graph | APM service maps | Trace waterfall and dependency tables in the APM app |
| Anomaly detection | Machine learning | Static thresholds |

Planned dashboards:

1. **Platform health**: ES cluster status, heap, indexing rate, rejected writes, disk watermarks.
2. **Kubernetes**: node and pod resources, restarts, events.
3. **Telemetry pipeline**: accepted/refused/sent items per collector, queue size, export failures.
4. **Applications**: RED metrics for Ascenda and the BJJ app, errors and slowest endpoints.
