# CI Hybrid Cluster Validation — Knowledge Entry

**Date**: 2026-03-27
**Task**: Q3 — CI Hybrid Cluster Validation
**Agent**: @qa-lead

## Summary

Created `scripts/ci-validate-cluster.sh` — a CI validation script that checks cluster health across 12 categories.

## Validation Checks

| # | Check | Pass Criteria | Category |
|---|-------|---------------|----------|
| 1 | Cluster connectivity | `kubectl cluster-info` succeeds | Critical |
| 2 | Nodes ready | All nodes show `Ready` status | Critical |
| 3 | System pods | All kube-system pods Running/Completed | Critical |
| 4 | Application pods | All default-ns pods Running | Important |
| 5 | Services | Count > 1 (not just kubernetes default) | Important |
| 6 | Named services | backend, frontend services exist | Important |
| 7 | Endpoints populated | No empty endpoint addresses | Important |
| 8 | CoreDNS | At least 1 coredns pod Running | Critical |
| 9 | PVCs | All PVCs Bound | Optional |
| 10 | NetworkPolicies | At least 1 configured | Optional |
| 11 | RBAC | ClusterRoleBindings present | Optional |
| 12 | Helm releases | All releases in `deployed` status | Optional |

## Usage

```bash
# Basic validation (stdout only)
scripts/ci-validate-cluster.sh

# Write results to knowledge base
scripts/ci-validate-cluster.sh --write-results
```

## CI Integration

Add to `.github/workflows/ci.yml` after cluster creation:

```yaml
- name: Validate cluster health
  run: scripts/ci-validate-cluster.sh --write-results
```

Results are written to `docs/knowledge/qa-testing/ci-results/<date>-cluster-validation.md`

## Exit Codes

- `0` — All critical and important checks passed
- `1` — One or more checks failed

Warnings (optional checks) do not cause non-zero exit.

## Design Decisions

1. **Warnings vs Failures**: Missing app pods and services are warnings for bare clusters, failures for deployed clusters
2. **Color output**: Detects TTY for colored vs plain output (CI-friendly)
3. **Helm check**: Optional, only runs if `helm` is available
4. **Write results**: Produces markdown with full `kubectl get` output for debugging
5. **No cluster modification**: Script is read-only, safe to run any time
