# TAP/Bridge Identity Derivation in Kind Clusters (E2)

**Date**: 2026-03-27
**Author**: @emulation-lead
**Task**: E2
**Depends on**: K2 (POD_NAME downward API), L2 (identity spec), E1 (QEMU startup fixes)
**Status**: implemented

## Summary

Updated all QEMU entrypoint scripts to derive per-instance network identity from the Kubernetes `POD_NAME` environment variable (provided by K2 via downward API). Each of the 9 emulator pods now gets a unique TAP interface, MAC address, IP address, and hostname — preventing collisions that would break NetBIOS discovery and DirectPlay LAN games.

## Changes Made

### 1. `containers/qemu-softgpu/entrypoint.sh`

- Added identity derivation block after configuration defaults
- Extracts `INSTANCE_INDEX` from `POD_NAME` ordinal (`${POD_NAME##*-}`)
- Defensive fallback chain: `POD_NAME` → `INSTANCE_INDEX` env → `0`
- Derives: `GUEST_HOSTNAME`, `GUEST_IP`, `GUEST_MAC`, `TAP_IF`, `GUEST_GATEWAY`, `GUEST_NETMASK`, `WORKGROUP`
- Updated QEMU `-net nic` line to include `macaddr=$GUEST_MAC`
- Added identity fields to startup log output
- **Preserved**: All E1 fixes (Xvfb, PulseAudio, health check, cleanup, process management)

### 2. `containers/qemu/entrypoint.sh`

- Same identity derivation block and QEMU macaddr fix as above
- Base QEMU container now also supports per-instance identity

### 3. `containers/qemu-softgpu/setup_network.sh`

- Added identity derivation (same POD_NAME → INSTANCE_INDEX → TAP_IF pattern)
- Bridge creation is now idempotent (`if ! ip link show` guard)
- Cleans up stale TAP interface before creating new one
- Added `set -euo pipefail` for strict error handling
- Added logging for each network operation

### 4. `containers/qemu-softgpu/run-qemu.sh`

- Added identity derivation for MAC and TAP
- Switched from `-netdev`/`-device` to `-net nic`/`-net tap` syntax (matches entrypoint convention)
- Added `macaddr=$GUEST_MAC` to NIC configuration
- Uses `$TAP_IF` instead of hardcoded `tap0`

## Identity Derivation Flow

```
POD_NAME=loco-loco-emulator-3    (K8s downward API, set by K2)
         │
         └─ INSTANCE_INDEX=${POD_NAME##*-} → 3
              │
              ├── TAP_IF=tap3
              ├── GUEST_MAC=52:54:00:10:00:03
              ├── GUEST_IP=192.168.10.13
              ├── GUEST_HOSTNAME=LOCO-03
              └── GUEST_GATEWAY=192.168.10.1
```

## Fallback Chain

```
POD_NAME set?  ──yes──> INSTANCE_INDEX = ${POD_NAME##*-}
    │no
    ▼
INSTANCE_INDEX env set? ──yes──> use it
    │no
    ▼
INSTANCE_INDEX = 0  (safe default for local/dev testing)
```

## Network Topology (per pod)

```
┌─────────────────────────────────────────┐
│  Pod: loco-loco-emulator-N              │
│                                         │
│  ┌──────────────┐    ┌──────────────┐   │
│  │ QEMU Guest   │    │ loco-br      │   │
│  │ MAC: ...0N   │◄──►│ 192.168.10.1 │   │
│  │ IP: .10+N    │    │   (bridge)   │   │
│  └──────┬───────┘    └──────┬───────┘   │
│         │                   │           │
│      tapN ──────────────────┘           │
│    (TAP interface)                      │
└─────────────────────────────────────────┘
```

## Verification

To verify identity derivation works correctly:

```bash
# In a running pod:
echo "POD_NAME=$POD_NAME"
echo "INSTANCE_INDEX=${POD_NAME##*-}"
ip link show tap${POD_NAME##*-}
ip link show loco-br
```

To verify all 9 instances have unique MACs:
```bash
kubectl exec -n loco loco-loco-emulator-{0..8} -- \
  grep -o 'macaddr=[^ ]*' /proc/$(pgrep qemu)/cmdline
```

## What Was NOT Changed

- E1 fixes: Xvfb display setup, PulseAudio, health monitoring, cleanup trap, process management — all preserved
- Bridge IP: remains `192.168.10.1/24` (gateway for all guests)
- VNC: still `:1` internal (port mapping handled by K8s service)
- GStreamer pipelines: untouched
- Disk image strategy: untouched
