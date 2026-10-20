# ADR-0004: Elastic Cloud on Kubernetes (ECK) on a 3-server k3s cluster

- **Status:** Accepted (replaces the package-based install of v0.1.0)
- **Date:** 2026-10-20

## Context

Installing Elasticsearch and Kibana from packages with Ansible works, but it means hand-writing
everything an operator already does: TLS certificates, bootstrap passwords, rolling upgrades,
scaling, and recovery. The target is an on-prem platform that looks like what teams run today.

## Decision

- **k3s** with 3 server nodes and embedded etcd (HA control plane, quorum of 2), with the bundled
  load balancer and ingress disabled.
- **ECK operator** (Helm) manages a 3-node Elasticsearch cluster (master+data+ingest, one pod per
  node through required anti-affinity) and Kibana.
- **Storage:** `local-path` volumes. Elasticsearch replicates shards itself, so node-local disks are
  the recommended and fastest option.
- **Exposure:** MetalLB in L2 mode gives fixed LAN IPs to Kibana and the OTel gateway.
- **Everything in-cluster is declarative:** one Helmfile (`k8s/`) plus a small local chart.

## Consequences

- ✅ ECK handles TLS, users, rolling upgrades and PodDisruptionBudgets.
- ✅ A version upgrade is a one-line change (`elastic.version`).
- ✅ Free: ECK runs on the Basic license by default (see ADR-0005).
- ❌ More moving parts than plain VMs (Kubernetes, operator, CRDs), and k3s itself has to be kept up to date.
- ❌ `local-path` volumes tie each ES pod to its node. Losing a node's disk means rebuilding that node's replica.
