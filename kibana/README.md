# Kibana assets

Exported dashboards, SLOs and alert rules live here, so the lab can be restored without any
clicking.

- `dashboards/*.ndjson`: export from *Stack Management → Saved objects*, import with
  `POST /api/saved_objects/_import`.
- Planned: manage SLOs and alerting rules as code with the
  [`elastic/elasticstack`](https://registry.terraform.io/providers/elastic/elasticstack/latest)
  Terraform provider.

Planned dashboards:

1. **Platform health**: ES cluster status, heap, indexing rate, rejected writes, disk watermarks.
2. **Telemetry pipeline**: accepted/refused/sent items per collector, queue size, export failures.
3. **Hosts**: CPU, memory, disk and network per VM.
4. **Applications**: RED metrics for Ascenda and the BJJ app, errors and slowest endpoints.
