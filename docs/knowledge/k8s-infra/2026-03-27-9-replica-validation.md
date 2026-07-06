# 9-Replica Scaling Validation (K2)

**Date**: 2026-03-27
**Author**: @k8s-lead
**Task**: K2
**Depends on**: K1 (namespace discovery), B1 (label matching), E1 (QEMU startup)
**Status**: implemented

## Summary

Validated and configured the Helm chart to support 9 emulator replicas with unique per-pod identity following the [instance identity spec](../lan-networking/instance-identity-spec.md). Each pod gets a deterministic network identity (IP, MAC, hostname, TAP interface) derived from its StatefulSet ordinal.

## Changes Made

### Helm Chart (`helm/loco-chart/`)

1. **values.yaml** — `replicas: 1` → `replicas: 9`
2. **values.yaml** — Removed static `TAP_IF: "tap0"` from `emulator.env` (now computed per-instance from ordinal)
3. **values.yaml** — Added `GUEST_GATEWAY`, `GUEST_NETMASK`, `WORKGROUP` to `emulator.env`
4. **templates/emulator-statefulset.yaml** — Added `POD_NAME` and `POD_IP` env vars via Kubernetes downward API. The entrypoint script derives `INSTANCE_INDEX`, `TAP_IF`, `GUEST_IP`, `GUEST_MAC`, `GUEST_HOSTNAME` from `POD_NAME` (ordinal = last segment after `-`).

### Kustomize

5. **kustomize/overlays/full/kustomization.yaml** — Added `emulator.env` block with network identity vars to match Helm values.

### Validation Script

6. **scripts/validate-9-replicas.sh** — 9-check validation script covering:
   - StatefulSet replica count
   - Pod Running status
   - Unique ordinals / INSTANCE_INDEX
   - NET_ADMIN capability
   - Discovery labels (`app.kubernetes.io/component=emulator`)
   - Headless service existence
   - Network identity env vars
   - VNC port exposure
   - Backend RBAC for discovery

## Architecture: Identity Derivation

```
StatefulSet ordinal (e.g., loco-loco-emulator-3)
  │
  ├── POD_NAME env var (downward API: metadata.name)
  │     └── entrypoint.sh: INSTANCE_INDEX=${POD_NAME##*-}  → 3
  │
  ├── GUEST_IP:       192.168.10.$((10 + 3))  → 192.168.10.13
  ├── GUEST_MAC:      52:54:00:10:00:03
  ├── GUEST_HOSTNAME: LOCO-03
  ├── TAP_IF:         tap3
  └── VNC:            :1 (internal), discoverable via headless SVC DNS
```

Kubernetes cannot do arithmetic in env values — the entrypoint must compute derived fields. The `POD_NAME` downward API is the bridge between K8s and the container runtime.

## What Already Worked

- **StatefulSet** — was already in use (not a Deployment)
- **Labels** — `app.kubernetes.io/component: emulator` and `app.kubernetes.io/part-of: lego-loco-cluster` already set (B1 fix)
- **NET_ADMIN + privileged** — already configured
- **Headless service** — already `clusterIP: None` with `publishNotReadyAddresses: true`
- **RBAC** — backend service account already has pod/statefulset list/watch

## What Needed Fixing

| Issue | Before | After |
|-------|--------|-------|
| Replica count | 1 | 9 |
| TAP_IF | Static `tap0` for all pods | Computed `tap{N}` per ordinal |
| Pod identity env | None | `POD_NAME` via downward API |
| Network identity | Not injected | `GUEST_GATEWAY`, `GUEST_NETMASK`, `WORKGROUP` |

## Entrypoint Contract

The entrypoint (`containers/qemu-softgpu/entrypoint.sh`) is expected to compute identity from `POD_NAME`:

```bash
INSTANCE_INDEX=${POD_NAME##*-}                           # e.g., 3
GUEST_HOSTNAME=${GUEST_HOSTNAME:-LOCO-0${INSTANCE_INDEX}}
GUEST_IP=${GUEST_IP:-192.168.10.$((10 + INSTANCE_INDEX))}
GUEST_MAC=${GUEST_MAC:-52:54:00:10:00:0${INSTANCE_INDEX}}
TAP_IF=${TAP_IF:-tap${INSTANCE_INDEX}}
```

This is a follow-up task for @emulation-lead (E2) to implement in the entrypoint.

## Validation

Run against a KIND or minikube cluster:

```bash
NAMESPACE=loco ./scripts/validate-9-replicas.sh
```

All 9 checks must pass for K2 to be considered complete.

## Cross-Team Dependencies

- **@emulation-lead (E2)**: Must update entrypoint to derive identity from `POD_NAME`
- **@lan-lead (L3)**: Port 2300 reachability test depends on all 9 pods running
- **@sre-lead (R1)**: Prometheus deployment assumes 9 scrape targets
- **@backend-lead**: `kubernetesDiscovery.js` already extracts ordinal from pod name — no changes needed
