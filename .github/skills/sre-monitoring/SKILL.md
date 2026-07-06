---
name: sre-monitoring
description: 'SRE and monitoring for Lego Loco Cluster. Covers Prometheus metrics, Grafana dashboards, health probing, SLO targets (95% startup, 500ms liveness), alerting rules, and recovery strategies.'
---

# SRE/Monitoring Skill

## When to Use
- Prometheus metric creation
- Grafana dashboard design
- Health probe debugging
- SLO target configuration
- Alerting and recovery

## Key Files
- `backend/services/probingService.js` — probing
- `docs/MONITORING.md` — monitoring arch
- `docs/SRE_PROBE_TESTING.md` — probe guide
- `debug_probe.js` — debug utility

## SLO Targets
- Startup success: ≥95%, Liveness: ≤500ms, Readiness: ≤300ms

## Procedure
1. Review health probing and metrics
2. Check `docs/knowledge/sre-monitoring/` for prior findings
3. Implement with proper metric naming
4. Verify SLO compliance
5. Document in `docs/knowledge/sre-monitoring/<date>-<topic>.md`

## Tasks: R1 (Prometheus), R2 (Grafana), R3 (alerting)
