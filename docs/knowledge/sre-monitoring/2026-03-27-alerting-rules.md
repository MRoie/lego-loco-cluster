# Alerting Rules — PrometheusRule Expansion

**Date**: 2026-03-27
**Author**: @sre-lead
**Task**: R3
**Status**: implemented

## Summary

Expanded the `PrometheusRule` resource in `helm/loco-chart/templates/prometheus-rules.yaml` with five additional alerts covering pod stability, stream quality, cluster availability, resource pressure, and disk integrity.

## Alerts Added

### 1. PodRestartLooping

| Field | Value |
|-------|-------|
| **Group** | `loco-pod-health` |
| **Expression** | `increase(kube_pod_container_status_restarts_total[15m]) > 3` |
| **For** | `0m` (fires immediately when threshold is crossed) |
| **Severity** | warning |
| **Rationale** | Pods restarting > 3× in 15 min indicate a CrashLoopBackOff or OOM cycle. Immediate notification lets SRE intervene before the backoff delay grows. |

**Required metric**: `kube_pod_container_status_restarts_total` — provided by `kube-state-metrics` (part of kube-prometheus-stack).

### 2. StreamQualityDegraded

| Field | Value |
|-------|-------|
| **Group** | `loco-stream-quality` |
| **Expression** | `avg(rate(stream_packets_lost_total[5m]) / (rate(stream_packets_received_total[5m]) + rate(stream_packets_lost_total[5m]))) > 0.05` |
| **For** | `5m` |
| **Severity** | warning |
| **Rationale** | > 5% average packet loss across all instances for 5 min means users are experiencing visible degradation. This triggers quality-adaptive streaming or manual intervention. |

**Required metrics**: `stream_packets_lost_total`, `stream_packets_received_total` — exposed by the backend stream quality monitor (`backend/services/streamQualityMonitor.js`).

### 3. AllInstancesDown

| Field | Value |
|-------|-------|
| **Group** | `loco-pod-health` |
| **Expression** | `count(up{job=~".*emulator.*"} == 1) == 0 or absent(up{job=~".*emulator.*"})` |
| **For** | `2m` |
| **Severity** | **critical** |
| **Rationale** | Zero healthy instances = complete outage. The `absent()` clause handles the case where no emulator targets exist at all. 2 min `for` avoids false positives during rolling updates. |

**Required metric**: `up` — built-in Prometheus scrape health metric.

### 4. HighMemoryUsage

| Field | Value |
|-------|-------|
| **Group** | `loco-pod-health` |
| **Expression** | `container_memory_working_set_bytes / container_spec_memory_limit_bytes > 0.9` |
| **For** | `5m` |
| **Severity** | warning |
| **Rationale** | At 90% of memory limit, containers are close to OOM-kill territory. 5 min avoids alerting on transient spikes. |

**Required metrics**: `container_memory_working_set_bytes`, `container_spec_memory_limit_bytes` — provided by cAdvisor (built into kubelet).

### 5. DiskImageCorruption

| Field | Value |
|-------|-------|
| **Group** | `loco-disk-health` |
| **Expression** | `qemu_disk_health_check_ok == 0` |
| **For** | `5m` |
| **Severity** | **critical** |
| **Rationale** | QCOW2 corruption can cause data loss and guest OS crashes. If the emulator exposes a `qemu_disk_health_check_ok` gauge (1 = healthy, 0 = failed), this catches it. |

**Required metric**: `qemu_disk_health_check_ok` — must be exposed by the emulator health endpoint. Currently proposed; will fire only when the metric exists.

## Dependency on Existing Rules

The original `prometheus-rules.yaml` (R1) already contained:

| Alert | Group |
|-------|-------|
| EmulatorDown | loco-emulator |
| HighPacketLoss | loco-emulator |
| DiscoveryStale | loco-backend |
| BackendHighErrorRate | loco-backend |

New alerts complement these with broader coverage.

## Gating

All rules are gated behind `{{ "{{" }}- if .Values.monitoring.enabled {{ "}}" }}`. No additional feature flag is needed since alerting rules are lightweight and only evaluate if Prometheus is scraping.

## Testing

1. **Dry-run**: `helm template loco helm/loco-chart --set monitoring.enabled=true | grep -A5 "alert:"`
2. **PromTool**: Extract the YAML rules block and validate with `promtool check rules rules.yaml`
3. **Unit tests**: Use Prometheus recording rules test framework to simulate metric values and verify alert firing

## References

- [prometheus-rules.yaml](../../../helm/loco-chart/templates/prometheus-rules.yaml) — the template
- [MONITORING.md](../../MONITORING.md) — runbook links
- [STORAGE_STRATEGY.md](../../STORAGE_STRATEGY.md) — disk health context
