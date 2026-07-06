# K1: Namespace Discovery Fix

**Date**: 2026-03-27  
**Status**: Fixed  
**Severity**: P0 — backend crashed on namespace discovery, blocking all instance endpoints

## Root Causes

Four bugs were identified and fixed:

### Bug 1 (P0): Property name mismatch in `instanceManager.js`

`getKubernetesInfo()` and `isUsingKubernetesDiscovery()` referenced `this.k8sDiscovery` — a property that was never defined. The actual property is `this.kubernetesDiscovery`.

This caused `TypeError: Cannot read properties of undefined (reading 'isAvailable')` whenever the `/api/kubernetes` or health endpoints were called, crashing the request handler.

**Fix**: Replaced all `this.k8sDiscovery` references with `this.kubernetesDiscovery`.

### Bug 2 (P0): Missing `discoverInstances()` method in `kubernetesDiscovery.js`

`InstanceManager` calls `this.discovery.discoverInstances()` on its discovery provider. `EndpointsDiscovery` implements this method, but `KubernetesDiscovery` only had `discoverEmulatorInstances()`. In legacy (pod-based) discovery mode, `this.discovery = this.kubernetesDiscovery`, so calling `discoverInstances()` returned `undefined`.

**Fix**: Added `discoverInstances()` as an alias for `discoverEmulatorInstances()`.

### Bug 3 (P1): Response body handling for newer `@kubernetes/client-node`

The `@kubernetes/client-node` v1.x+ returns Kubernetes objects directly from API calls, not wrapped in `{ body: ... }`. `endpointsDiscovery.js` correctly handled this with `const body = response.body || response;`, but `kubernetesDiscovery.js` always accessed `response.body`, resulting in `undefined` items on newer client versions.

**Fix**: Applied the `response.body || response` pattern to `discoverEmulatorInstances()`, `getServicesInfo()`, and `getStatefulSetsInfo()`.

### Bug 4 (minor): Namespace fallback defaulted to `'default'` instead of `'loco'`

The `init()` method fell back to namespace `'default'` when neither `KUBERNETES_NAMESPACE` env var nor the service account namespace file existed. This mismatched the Helm chart `values.yaml` which deploys to namespace `loco`.

**Fix**: Changed the fallback from `'default'` to `'loco'` to align with `helm/loco-chart/values.yaml`.

## Files Changed

| File | Change |
|------|--------|
| `backend/services/kubernetesDiscovery.js` | Fixed namespace fallback, response body handling, added `discoverInstances()` alias |
| `backend/services/instanceManager.js` | Fixed `k8sDiscovery` → `kubernetesDiscovery` references |
| `backend/tests/kubernetesDiscovery.test.js` | Fixed dynamic import to `require()` (CommonJS compat) |

## Verification

- All 6 existing tests in `kubernetesDiscovery.test.js` pass.
- Label selectors (`app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster`) match the Helm StatefulSet template.
- Helm `backend-deployment.yaml` correctly injects `KUBERNETES_NAMESPACE` from `metadata.namespace` via `fieldRef`, so in-cluster the env var path is used.
- RBAC grants `get/list/watch` on `pods`, `services`, `endpoints`, and `statefulsets` in the chart namespace.

## Architecture Notes

- **Primary discovery path**: `InstanceManager` → `EndpointsDiscovery` (mode `kubernetes-endpoints`) — queries the headless Service endpoints.
- **Legacy discovery path**: `InstanceManager` → `KubernetesDiscovery` (pod-based) — queries pods directly by label.
- Both paths now implement `discoverInstances()` as expected by `InstanceManager`.
