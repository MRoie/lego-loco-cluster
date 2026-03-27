# K4: Endpoints-Based Service Discovery

**Date**: 2026-03-27  
**Status**: Implemented  
**Ref**: Production Roadmap Phase 2.3 (SD-001 through SD-004)

## Summary

Added Endpoints-based discovery as an alternative strategy inside `kubernetesDiscovery.js`, making the existing pod-based discovery and the new Endpoints approach selectable via a single configuration knob.

## Discovery Strategies

| Strategy | Env var `DISCOVERY_STRATEGY` | Behaviour |
|----------|------------------------------|-----------|
| **pods** | `pods` | List pods by label selector (original method) |
| **endpoints** | `endpoints` | Query the Endpoints resource for the emulator headless Service |
| **auto** (default) | `auto` | Try Endpoints first; if the call fails, fall back to pod-based discovery |

The headless Service name defaults to `loco-loco-emulator` and is configurable with `EMULATOR_SERVICE_NAME`.

## How Endpoints Discovery Works

1. `discoverViaEndpoints()` calls `readNamespacedEndpoints({ name, namespace })` for the emulator headless service.
2. Each Endpoint subset contains `addresses` (ready pods) and `notReadyAddresses` (not-yet-ready pods).
3. For every address, an instance object is built with DNS name `<podName>.<serviceName>.<namespace>.svc.cluster.local`, IP, ports, and readiness.
4. `watchEndpointsChanges(callback)` sets up a watch on the Endpoints resource (filtered by `fieldSelector`) so cache invalidation is near-instant.

## Fallback Behaviour (`auto` strategy)

`discoverViaEndpoints()` returns `null` on failure (network error, missing service, RBAC denial). The `discoverInstances()` entry-point checks for `null` and falls back to `discoverEmulatorInstances()` (pod-based). This ensures zero downtime during migration — if the headless Service hasn't been created yet, pod discovery continues to work.

## Relationship to Existing Files

- **`endpointsDiscovery.js`** — standalone EndpointsDiscovery class used when `InstanceManager` is in `kubernetes-endpoints` mode. Remains as-is for backward compatibility.
- **`kubernetesDiscovery.js`** — now contains both strategies internally, selectable via `DISCOVERY_STRATEGY`. This is the path forward; once validated in production, `InstanceManager` can use `KubernetesDiscovery` directly for all modes.

## RBAC Requirements

The backend ServiceAccount needs `get` and `watch` on `endpoints` in its ClusterRole/Role:

```yaml
- apiGroups: [""]
  resources: ["endpoints"]
  verbs: ["get", "list", "watch"]
```

This is in addition to the existing `pods`, `services`, `statefulsets` permissions.

## Files Changed

| File | Change |
|------|--------|
| `backend/services/kubernetesDiscovery.js` | Added `discoverViaEndpoints()`, `_buildEndpointInstance()`, `_mapEndpointPorts()`, `watchEndpointsChanges()`. Replaced `discoverInstances()` alias with strategy-aware router (`endpoints` / `pods` / `auto`). Added constructor fields for `discoveryStrategy`, `serviceName`, `endpointsWatchRequest`. |
| `docs/knowledge/k8s-infra/2026-03-27-endpoints-discovery.md` | This file — knowledge entry. |

## Testing Notes

- Set `DISCOVERY_STRATEGY=pods` to preserve original behaviour.
- Set `DISCOVERY_STRATEGY=endpoints` for pure Endpoints mode (requires headless service + RBAC).
- Default `auto` is safe for incremental rollout — no behaviour change until the headless service exists.
- Integration test: deploy headless service in Minikube, verify `discoverViaEndpoints()` returns correct instances, then delete service and verify pod fallback activates.
