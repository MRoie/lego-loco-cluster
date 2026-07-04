# Prometheus Operator Deployment — 2026-03-27

## Summary

Integrated Prometheus monitoring into the Lego Loco Cluster Helm chart and created an
idempotent deployment script for the kube-prometheus-stack.

## What was added

| File | Purpose |
|------|---------|
| `helm/loco-chart/templates/servicemonitor.yaml` | ServiceMonitor CRDs — tells Prometheus *what* to scrape |
| `helm/loco-chart/templates/prometheus-rules.yaml` | PrometheusRule CRD — alerting rules evaluated by Prometheus |
| `helm/loco-chart/values.yaml` | New `monitoring.*` section (disabled by default) |
| `scripts/deploy-prometheus.sh` | One-command Prometheus Operator install via Helm |

## ServiceMonitor targets

1. **Backend** (`loco-backend` service, port `http` / 3001) — scrapes `/metrics`
   exposed by `prom-client`. Metrics include `http_request_duration_seconds`,
   `active_connections_total`, `vnc_bytes_transferred_total`,
   `vnc_framebuffer_updates_total`, and Node.js default metrics.

2. **Emulator** (`loco-emulator` headless service, port `health` / 8080) — scrapes
   `/health` on each emulator pod. Returns JSON health data covering QEMU process,
   VNC, audio, CPU, memory, and network.

## Alert rules

| Alert | Condition | Severity |
|-------|-----------|----------|
| `EmulatorDown` | `up{job=~".*emulator.*"} == 0` for 5 min | critical |
| `HighPacketLoss` | TX active but RX stalled for 2 min | warning |
| `DiscoveryStale` | Discovery refresh > 2 min old | warning |
| `BackendHighErrorRate` | 5xx rate > 5% for 5 min | warning |

## How to enable

```bash
# 1. Deploy Prometheus Operator (once per cluster)
bash scripts/deploy-prometheus.sh

# 2. Enable monitoring in the loco chart
helm upgrade --install loco helm/loco-chart/ -n loco --set monitoring.enabled=true
```

## Design decisions

- **Toggleable** — `monitoring.enabled: false` by default so the chart works without
  the Prometheus Operator CRDs installed.
- **Release label** — ServiceMonitors carry `release: kube-prometheus` (configurable
  via `monitoring.prometheusRelease`) so Prometheus discovers them.
- **Idempotent script** — `deploy-prometheus.sh` uses `helm upgrade --install` and
  `kubectl apply` for safe re-runs.
- **Namespace-scoped discovery** — Prometheus only watches the `loco` and `monitoring`
  namespaces to keep the blast radius small.
- **Grafana on NodePort 30300** — convenient for minikube / dev access without Ingress.

## Future work

- Export a pre-built Grafana dashboard JSON for the loco cluster.
- Add `loco_discovery_last_refresh_timestamp_seconds` gauge in the backend to power
  the `DiscoveryStale` alert.
- Add PagerDuty / Slack receiver configuration to Alertmanager.
