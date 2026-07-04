# Per-Instance Network Identity Specification

**Date**: 2026-03-27
**Author**: @lan-lead
**Task**: L2
**Status**: spec

## Summary

This document defines the unique network identity system for the 9 QEMU Windows 98 instances (index 0–8) running in Kubernetes pods. Every instance must have a deterministic, collision-free identity so that NetBIOS name resolution, DirectPlay game discovery, and TCP/IP connectivity all work across the LOCOLAND LAN.

## Design Goals

1. **Deterministic** — identity derived from a single integer instance index `N` (0–8).
2. **Collision-free** — no two instances share any identity field.
3. **Windows 98 compatible** — hostnames ≤ 15 chars, NetBIOS-safe.
4. **Injection via environment variables** — Kubernetes pod spec → entrypoint script → QEMU CLI → guest OS, with no manual steps.

---

## Identity Fields

### IP Address
- **Scheme**: `192.168.10.(10 + N)`
- **Subnet**: `192.168.10.0/24`
- **Gateway**: `192.168.10.1` (bridge `loco-br`)
- **Range**: `192.168.10.10` – `192.168.10.18`

### Hostname / Computer Name
- **Scheme**: `LOCO-0N` (e.g., `LOCO-00` through `LOCO-08`)
- **Length**: 7 characters (well within 15-char NetBIOS limit)
- **Case**: uppercase (Windows 98 NetBIOS convention)
- **Used as**: Linux container hostname, Windows 98 Computer Name, NetBIOS name

### MAC Address
- **Scheme**: `52:54:00:10:00:0N`
- **Prefix**: `52:54:00` — QEMU locally-administered OUI
- **Uniqueness byte**: last octet `0N` maps directly to instance index
- **Range**: `52:54:00:10:00:00` – `52:54:00:10:00:08`

### TAP Interface
- **Scheme**: `tap{N}` (e.g., `tap0` through `tap8`)
- **Bridge**: all TAP interfaces are attached to `loco-br`

### VNC Display
- **Scheme**: VNC display `:1` inside each pod, exposed as host port `590N`
- **Each pod** runs its own isolated VNC server

---

## Instance Identity Table

| Index (N) | IP Address      | Hostname | Computer Name | MAC Address          | TAP   | VNC Port | Role         |
|-----------|-----------------|----------|---------------|----------------------|-------|----------|--------------|
| 0         | 192.168.10.10   | LOCO-00  | LOCO-00       | 52:54:00:10:00:00    | tap0  | 5900     | Game Server  |
| 1         | 192.168.10.11   | LOCO-01  | LOCO-01       | 52:54:00:10:00:01    | tap1  | 5901     | Client 1     |
| 2         | 192.168.10.12   | LOCO-02  | LOCO-02       | 52:54:00:10:00:02    | tap2  | 5902     | Client 2     |
| 3         | 192.168.10.13   | LOCO-03  | LOCO-03       | 52:54:00:10:00:03    | tap3  | 5903     | Client 3     |
| 4         | 192.168.10.14   | LOCO-04  | LOCO-04       | 52:54:00:10:00:04    | tap4  | 5904     | Client 4     |
| 5         | 192.168.10.15   | LOCO-05  | LOCO-05       | 52:54:00:10:00:05    | tap5  | 5905     | Client 5     |
| 6         | 192.168.10.16   | LOCO-06  | LOCO-06       | 52:54:00:10:00:06    | tap6  | 5906     | Client 6     |
| 7         | 192.168.10.17   | LOCO-07  | LOCO-07       | 52:54:00:10:00:07    | tap7  | 5907     | Client 7     |
| 8         | 192.168.10.18   | LOCO-08  | LOCO-08       | 52:54:00:10:00:08    | tap8  | 5908     | Client 8     |

---

## Identity Injection Pipeline

Identity flows through four layers, each consuming the instance index `N`:

```
┌───────────────────────────────────────────────────────────────────┐
│ 1. Kubernetes Pod Spec                                            │
│    env:                                                           │
│      INSTANCE_INDEX: "N"           ← StatefulSet ordinal          │
│      GUEST_HOSTNAME: "LOCO-0N"                                    │
│      GUEST_IP: "192.168.10.(10+N)"                                │
│      GUEST_MAC: "52:54:00:10:00:0N"                               │
│      TAP_IF: "tapN"                                               │
│      BRIDGE: "loco-br"                                            │
│      GUEST_GATEWAY: "192.168.10.1"                                │
│      GUEST_NETMASK: "255.255.255.0"                               │
│      WORKGROUP: "LOCOLAND"                                        │
│                                                                   │
├───────────────────────────────────────────────────────────────────┤
│ 2. Entrypoint Script (entrypoint.sh)                              │
│    - Reads env vars                                               │
│    - Creates bridge: ip link add $BRIDGE type bridge              │
│    - Creates TAP:    ip tuntap add $TAP_IF mode tap               │
│    - Attaches TAP to bridge                                       │
│    - Derives QEMU flags from env vars                             │
│                                                                   │
├───────────────────────────────────────────────────────────────────┤
│ 3. QEMU Command Line                                              │
│    -net nic,model=ne2k_pci,macaddr=$GUEST_MAC                    │
│    -net tap,ifname=$TAP_IF,script=no,downscript=no                │
│                                                                   │
├───────────────────────────────────────────────────────────────────┤
│ 4. Windows 98 Guest OS                                            │
│    - Static IP, gateway, netmask via TCP/IP properties            │
│    - Computer Name set to $GUEST_HOSTNAME                         │
│    - Workgroup set to LOCOLAND                                    │
│    - NetBIOS over TCP/IP enabled                                  │
└───────────────────────────────────────────────────────────────────┘
```

### Layer 1: Kubernetes Pod Spec

The pod should be managed by a **StatefulSet** so each replica gets a stable ordinal index. Environment variables are computed from the ordinal:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loco-emulator
spec:
  replicas: 9
  serviceName: loco-emulator
  template:
    spec:
      containers:
        - name: qemu
          image: ghcr.io/mroie/qemu-softgpu:latest
          env:
            - name: INSTANCE_INDEX
              valueFrom:
                fieldRef:
                  fieldPath: metadata.labels['apps.kubernetes.io/pod-index']
            - name: GUEST_HOSTNAME
              value: "LOCO-0$(INSTANCE_INDEX)"  # see init-container below
            - name: GUEST_IP
              value: ""  # computed by init container
            - name: GUEST_MAC
              value: ""  # computed by init container
            - name: TAP_IF
              value: ""  # computed by init container
            - name: BRIDGE
              value: "loco-br"
            - name: GUEST_GATEWAY
              value: "192.168.10.1"
            - name: GUEST_NETMASK
              value: "255.255.255.0"
            - name: WORKGROUP
              value: "LOCOLAND"
```

Since Kubernetes does not support arithmetic in env var values, an **init container** (or the entrypoint itself) must derive the computed fields:

```bash
# Derive all identity fields from INSTANCE_INDEX
N=${INSTANCE_INDEX:?INSTANCE_INDEX env var is required}
export GUEST_HOSTNAME="LOCO-0${N}"
export GUEST_IP="192.168.10.$((10 + N))"
export GUEST_MAC="52:54:00:10:00:0${N}"
export TAP_IF="tap${N}"
```

### Layer 2: Entrypoint Script Changes

The current entrypoint reads `BRIDGE` and `TAP_IF` from env with defaults. The following changes are required:

```bash
# --- Current (hardcoded defaults) ---
BRIDGE=${BRIDGE:-loco-br}
TAP_IF=${TAP_IF:-tap0}

# --- Required additions ---
INSTANCE_INDEX=${INSTANCE_INDEX:-0}
GUEST_HOSTNAME=${GUEST_HOSTNAME:-LOCO-0${INSTANCE_INDEX}}
GUEST_IP=${GUEST_IP:-192.168.10.$((10 + INSTANCE_INDEX))}
GUEST_MAC=${GUEST_MAC:-52:54:00:10:00:0${INSTANCE_INDEX}}
TAP_IF=${TAP_IF:-tap${INSTANCE_INDEX}}
GUEST_GATEWAY=${GUEST_GATEWAY:-192.168.10.1}
GUEST_NETMASK=${GUEST_NETMASK:-255.255.255.0}
WORKGROUP=${WORKGROUP:-LOCOLAND}
```

### Layer 3: QEMU Command Line

The current QEMU NIC line does **not** set a MAC address:

```bash
# Current
-net nic,model=ne2k_pci -net tap,ifname=$TAP_IF,script=no,downscript=no

# Required — add macaddr parameter
-net nic,model=ne2k_pci,macaddr=$GUEST_MAC \
-net tap,ifname=$TAP_IF,script=no,downscript=no
```

The `macaddr` parameter on `-net nic` is the only way to assign a per-instance MAC in QEMU's legacy NIC syntax. This MAC is what Windows 98 sees as its Ethernet adapter address.

### Layer 4: Windows 98 Guest Configuration

Guest-side settings must be baked into the disk image or applied via an autoexec script. Each instance needs:

| Setting | Location in Windows 98 | Value |
|---------|----------------------|-------|
| IP Address | Network → TCP/IP → Properties → IP Address | `192.168.10.(10+N)` |
| Subnet Mask | Network → TCP/IP → Properties → IP Address | `255.255.255.0` |
| Default Gateway | Network → TCP/IP → Properties → Gateway | `192.168.10.1` |
| DNS | Network → TCP/IP → Properties → DNS | (none required) |
| Computer Name | Network → Identification → Computer Name | `LOCO-0N` |
| Workgroup | Network → Identification → Workgroup | `LOCOLAND` |
| Description | Network → Identification → Description | `Lego Loco Instance N` |

#### Registry Keys (Windows 98)

These registry locations store the identity values:

```
; Computer Name & Workgroup
HKLM\System\CurrentControlSet\Services\VxD\VNETSUP
  "ComputerName"="LOCO-0N"
  "Workgroup"="LOCOLAND"
  "Comment"="Lego Loco Instance N"

; TCP/IP static configuration (adapter-specific)
HKLM\System\CurrentControlSet\Services\Class\NetTrans\0000
  "IPAddress"="192.168.10.(10+N)"
  "IPMask"="255.255.255.0"
  "DefaultGateway"="192.168.10.1"

; NetBIOS
HKLM\System\CurrentControlSet\Services\VxD\MSTCP
  "EnableDNS"="0"
  "BcastNameQueryCount"="3"
  "NameSrvQueryCount"="3"
```

#### Network Components Required

The Windows 98 guest must have these network components installed:

1. **Client for Microsoft Networks** — enables Network Neighborhood browsing
2. **NE2000 Compatible** (ne2k_pci driver) — NIC driver matching QEMU's emulated card
3. **TCP/IP** — bound to the NE2000 adapter
4. **File and Printer Sharing** — enables SMB shares (optional but useful for game data)
5. **NetBIOS over TCP/IP** — must be enabled for name resolution (enabled by default with Client for Microsoft Networks)

#### Guest Config Strategies

| Strategy | Description | Pros | Cons |
|----------|-------------|------|------|
| **Per-instance disk image** | 9 separate qcow2 images, each pre-configured | Simple, no runtime patching | 9× storage, harder to maintain |
| **Shared base + overlay** | Single base image, qcow2 backing file per instance | Storage efficient | Still need identity patching |
| **Runtime registry patching** | Single base image, patch registry at boot via shared folder script | Single image, fully dynamic | Requires guest-side scripting, fragile |
| **DHCP + hostname script** | Run a DHCP server on the bridge, assign per-MAC | Automatic IP, minimal guest config | Still need hostname/workgroup set, DHCP complexity |

**Recommended**: Shared base image + runtime registry patching via an `AUTOEXEC.BAT` or startup script that reads identity from a QEMU-mounted config file (e.g., a floppy image or 9pfs share). This gives dynamic identity with minimal disk duplication.

---

## Validation Checklist

After identity injection, verify the following from inside each guest:

```
C:\> ipconfig                       → correct IP, mask, gateway
C:\> net config workstation          → correct computer name, workgroup
C:\> nbtstat -n                      → correct NetBIOS name registered
C:\> ping 192.168.10.1              → gateway reachable
C:\> ping 192.168.10.11             → peer instance reachable
C:\> net view                        → other instances visible in Network Neighborhood
```

---

## Cross-Team Dependencies

| Dependency | Owner | What's Needed | From This Spec |
|------------|-------|---------------|----------------|
| QEMU `-net nic,macaddr=` flag | @emulation-lead | Add `macaddr=$GUEST_MAC` to QEMU command line in entrypoint | Section: Layer 3 |
| Pod env vars in StatefulSet | @k8s-lead | Add `INSTANCE_INDEX`, `GUEST_*` env vars to pod spec; use StatefulSet for stable ordinals | Section: Layer 1 |
| Guest OS config scripts | @win98-lead | Set static IP, hostname, workgroup in Windows 98 registry per identity table; implement runtime patching strategy | Section: Layer 4 |
| Init container or entrypoint derivation logic | @emulation-lead | Derive computed env vars from `INSTANCE_INDEX` in entrypoint.sh | Section: Layer 2 |
| NetworkPolicy for game ports | @k8s-lead | Allow TCP/UDP 2300, 47624, 137-139 between all loco-emulator pods | Ref: network-topology.md |

---

## Open Questions

1. **Guest config injection method** — which runtime patching strategy will @win98-lead implement? (floppy image, 9pfs share, or pre-baked images)
2. **DNS** — is a DNS server on the bridge needed, or is NetBIOS name resolution sufficient for Lego Loco's DirectPlay?
3. **DHCP vs static** — the spec assumes static IPs; if DHCP is preferred, a `dnsmasq` instance on the bridge could assign IPs by MAC reservation.

---

## Related Documents

- [network-topology.md](network-topology.md) — network architecture diagram and port map
- [lan-blockers-tracker.md](lan-blockers-tracker.md) — LAN blocker #1 depends on this spec
- `config/instances.json` — current instance configuration (needs `INSTANCE_INDEX` field)
- `containers/qemu-softgpu/entrypoint.sh` — entrypoint requiring identity env var support
- `containers/qemu/entrypoint.sh` — alternative entrypoint, same changes needed
