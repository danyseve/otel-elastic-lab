# k8s/ - in-cluster platform

Everything that runs inside the k3s cluster is deployed by [`helmfile.yaml.gotmpl`](helmfile.yaml.gotmpl),
in this order:

| Release | Chart | What it does |
|---|---|---|
| `cert-manager` | jetstack/cert-manager | Lab CA, Kibana and gateway certificates, OTel Operator webhooks |
| `metallb` | metallb/metallb | Fixed LAN IPs for `LoadBalancer` Services (L2 mode) |
| `eck-operator` | elastic/eck-operator | Elastic Cloud on Kubernetes, Basic license |
| `lab-platform` | `./charts/lab-platform` | CA issuer, IP pool, `Elasticsearch` + `Kibana` resources, collector user/role, external OTLP Service |
| `otel` | open-telemetry/opentelemetry-kube-stack | OTel Operator + agent DaemonSet, cluster collector and EDOT gateway |

## Usage

```bash
export KUBECONFIG=../ansible/.kube/config
cp values/lab.yaml.example values/lab.yaml   # git-ignored: your IPs and domain
helmfile apply
kubectl -n observability get elasticsearch,kibana,opentelemetrycollectors
```

## Things to check on the first deployment

- **Chart versions** in the Helmfile are pinned. Check for newer ones with `helm search repo <chart> --versions`.
- **EDOT gateway**: image `docker.elastic.co/elastic-agent/elastic-otel-collector:<version>`. The names
  of the `elasticapm` processor/connector depend on the EDOT version.
- **Collector labels**: the external Service selects `app.kubernetes.io/name: otel-gateway-collector`.
  Confirm with `kubectl -n observability get pods --show-labels`.
- **kube-stack presets** add the receivers to the `cluster` collector pipelines. Check the generated
  `OpenTelemetryCollector` objects if a pipeline has no receivers.
- **ECK secrets** used by the gateway: `lab-es-http-certs-public` (ES CA) and `otel-writer-user`.
