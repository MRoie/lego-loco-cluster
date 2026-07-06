# B1: Service Label Matching Fix

**Date**: 2026-03-27  
**Priority**: P0  
**Status**: RESOLVED  

## Summary

Audited all label selectors in backend Kubernetes discovery code against Helm chart templates and Kustomize overlays. Found and fixed a test mismatch and a missing environment variable injection that made service discovery fragile.

## Audit Results

### Backend Label Selectors

| Location | Selector | Purpose |
|---|---|---|
| `kubernetesDiscovery.js:119` | `app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster` | Pod discovery |
| `kubernetesDiscovery.js:354` | `app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster` | Pod watch |
| `kubernetesDiscovery.js:293` | `app.kubernetes.io/part-of=lego-loco-cluster` | Services info (all components) |
| `kubernetesDiscovery.js:430` | `app.kubernetes.io/part-of=lego-loco-cluster` | StatefulSets info (all components) |
| `endpointsDiscovery.js` | *(uses service name, no label selector)* | Endpoints-based discovery |
| `instanceManager.js:14` | `EMULATOR_SERVICE_NAME` env or default `loco-loco-emulator` | Service name for endpoints |

### Helm Template Labels (emulator-statefulset.yaml)

**Pod template labels:**
- `app: {{ include "loco.fullname" . }}-emulator`
- `app.kubernetes.io/component: emulator`
- `app.kubernetes.io/part-of: lego-loco-cluster`
- `app.kubernetes.io/name: lego-loco-emulator`

**StatefulSet matchLabels selector:**
- `app: {{ include "loco.fullname" . }}-emulator`
- `app.kubernetes.io/component: emulator`
- `app.kubernetes.io/part-of: lego-loco-cluster`

**Headless Service selector (emulator-service.yaml):**
- `app: {{ include "loco.fullname" . }}-emulator`
- `app.kubernetes.io/component: emulator`
- `app.kubernetes.io/part-of: lego-loco-cluster`

### Kustomize Overlays

No label overrides in `kustomize/base/` or `kustomize/overlays/full/`. Both reference the Helm chart via `helmCharts` with `valuesInline` only.

## Alignment Status

| Backend Selector | Helm Pod Labels | Match? |
|---|---|---|
| `component=emulator` | `component: emulator` | ✅ |
| `part-of=lego-loco-cluster` | `part-of: lego-loco-cluster` | ✅ |

**Primary label `app.kubernetes.io/component: emulator` is used consistently on both sides.**

## Issues Found & Fixed

### 1. Test Label Selector Mismatch (FIXED)

**File**: `backend/tests/kubernetesDiscovery.test.js:100`

The test used `app.kubernetes.io/component=emulator` (single label) while production code uses `app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster` (two labels). This meant the test was asserting against the wrong selector.

**Fix**: Updated test to use the full two-label selector matching production code.

### 2. Missing EMULATOR_SERVICE_NAME in Helm Backend Deployment (FIXED)

**File**: `helm/loco-chart/templates/backend-deployment.yaml`

The `instanceManager.js` defaults `EMULATOR_SERVICE_NAME` to `'loco-loco-emulator'` — a hardcoded value that only works when the Helm release name is `loco` and chart name is `loco`. If the release name changes, endpoints discovery would silently break because it would query a service that doesn't exist.

**Fix**: Added two environment variables to the backend container in the Helm deployment:
- `EMULATOR_SERVICE_NAME`: `{{ include "loco.fullname" . }}-emulator` — dynamically computed from Helm release/chart name
- `DISCOVERY_MODE`: `kubernetes-endpoints` — explicit rather than relying on default

### 3. No Issues in Kustomize (CONFIRMED)

Kustomize overlays don't override any labels. They reference the Helm chart directly so labels are inherited.

## Files Modified

1. `backend/tests/kubernetesDiscovery.test.js` — Fixed label selector in test to match production code
2. `helm/loco-chart/templates/backend-deployment.yaml` — Added `EMULATOR_SERVICE_NAME` and `DISCOVERY_MODE` env vars

## Verification

To verify label alignment after deployment:
```bash
# Check labels on emulator pods
kubectl get pods -n loco -l app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster --show-labels

# Check the backend sees the correct env vars
kubectl exec -n loco deploy/loco-loco-backend -- env | grep -E 'EMULATOR_SERVICE|DISCOVERY_MODE'

# Check endpoints are populated
kubectl get endpoints -n loco loco-loco-emulator
```
