# DHCP Collision Prevention Strategy

**Date**: 2026-03-27
**Author**: @lan-lead
**Task**: L7
**Status**: resolved
**Blocker**: #5

## Summary

This document explains why static IP assignment is the preferred strategy for the 9 QEMU Windows 98 instances and provides a fallback dnsmasq configuration if DHCP is ever needed.

## Why Static IPs Over DHCP

The L2 instance identity spec (`instance-identity-spec.md`) defines a deterministic static IP scheme: `192.168.10.(10 + N)` for instance index N (0–8). Static IPs are preferred for the following reasons:

| Factor | Static IP | DHCP |
|--------|-----------|------|
| **Determinism** | IP derived from instance index — always the same | Lease order depends on boot timing, race conditions with 9 simultaneous requests |
| **Collision risk** | Zero — each index maps to exactly one IP | Possible if dnsmasq pool overlaps, leases expire mid-session, or multiple DHCP servers appear |
| **Win98 compatibility** | TCP/IP properties set once in guest, no extra software | Win98 DHCP client is basic; no DUID, limited lease renewal |
| **NetBIOS alignment** | Computer name ↔ IP mapping is constant, simplifying WINS/lmhosts | IP may change, breaking pre-configured WINS entries |
| **DirectPlay discovery** | Host IP is known in advance — clients can connect directly | Host IP unknown until lease granted, requires extra discovery step |
| **Debuggability** | `ping 192.168.10.12` always reaches LOCO-02 | Must check lease table to find which instance got which IP |
| **No extra daemon** | No DHCP server process needed on the bridge | Requires dnsmasq running on bridge, adding a failure point |
| **Kubernetes fit** | Entrypoint derives IP from `INSTANCE_INDEX` env var — no external dependency | Need a sidecar or init container running dnsmasq |

### Conclusion

For 9 instances on a single `/24` bridge with known MAC addresses, static IPs are simpler, safer, and fully sufficient. DHCP adds complexity without benefit.

## Current Static IP Scheme

From the L2 identity spec:

```
Bridge:  loco-br  192.168.10.1/24  (gateway)
Instance 0: 192.168.10.10  MAC 52:54:00:10:00:00  LOCO-00
Instance 1: 192.168.10.11  MAC 52:54:00:10:00:01  LOCO-01
Instance 2: 192.168.10.12  MAC 52:54:00:10:00:02  LOCO-02
Instance 3: 192.168.10.13  MAC 52:54:00:10:00:03  LOCO-03
Instance 4: 192.168.10.14  MAC 52:54:00:10:00:04  LOCO-04
Instance 5: 192.168.10.15  MAC 52:54:00:10:00:05  LOCO-05
Instance 6: 192.168.10.16  MAC 52:54:00:10:00:06  LOCO-06
Instance 7: 192.168.10.17  MAC 52:54:00:10:00:07  LOCO-07
Instance 8: 192.168.10.18  MAC 52:54:00:10:00:08  LOCO-08
```

The entrypoint scripts (`containers/qemu/entrypoint.sh`, `containers/qemu-softgpu/entrypoint.sh`) already derive all identity fields from `INSTANCE_INDEX`. The QEMU NIC line includes `macaddr=$GUEST_MAC`. The guest OS is configured with the static IP via registry patching at boot.

## Fallback: dnsmasq with MAC-Based Reservations

If a future scenario requires DHCP (e.g., additional dynamic guests beyond the core 9, or a development environment where guest images lack pre-baked IPs), use dnsmasq on the bridge with **MAC-based reservations** to guarantee the same collision-free mapping.

### dnsmasq Configuration

Create `/etc/dnsmasq.d/loco-bridge.conf` on the bridge host (or in the pod running dnsmasq):

```ini
# loco-br DHCP server configuration
# Bind only to the game bridge — do not interfere with host networking
interface=loco-br
bind-interfaces

# DHCP range: .10 to .18 for the 9 instances, plus .100-.120 for dynamic guests
dhcp-range=192.168.10.100,192.168.10.120,255.255.255.0,12h

# MAC-based reservations — guarantees each instance gets its static IP
# even when using DHCP. The MAC must match the QEMU -net nic macaddr.
dhcp-host=52:54:00:10:00:00,LOCO-00,192.168.10.10,infinite
dhcp-host=52:54:00:10:00:01,LOCO-01,192.168.10.11,infinite
dhcp-host=52:54:00:10:00:02,LOCO-02,192.168.10.12,infinite
dhcp-host=52:54:00:10:00:03,LOCO-03,192.168.10.13,infinite
dhcp-host=52:54:00:10:00:04,LOCO-04,192.168.10.14,infinite
dhcp-host=52:54:00:10:00:05,LOCO-05,192.168.10.15,infinite
dhcp-host=52:54:00:10:00:06,LOCO-06,192.168.10.16,infinite
dhcp-host=52:54:00:10:00:07,LOCO-07,192.168.10.17,infinite
dhcp-host=52:54:00:10:00:08,LOCO-08,192.168.10.18,infinite

# Gateway and DNS
dhcp-option=option:router,192.168.10.1
dhcp-option=option:dns-server,192.168.10.1

# NetBIOS / WINS options (for Windows 98 clients)
dhcp-option=44,192.168.10.1   # WINS server (bridge acts as WINS if needed)
dhcp-option=46,8               # NetBIOS node type: hybrid (use WINS then broadcast)

# Logging
log-dhcp
log-facility=/var/log/dnsmasq-loco.log
```

### Key Design Decisions

1. **`dhcp-host` with `infinite` lease**: Reservations never expire, preventing mid-game IP changes.
2. **Dynamic range starts at `.100`**: The reserved `.10–.18` range is excluded from the dynamic pool, so even if a reservation fails, no dynamic client can steal a reserved IP.
3. **`bind-interfaces`**: dnsmasq listens only on `loco-br`, not on the pod's eth0 or any other interface.
4. **Hostname in reservation**: dnsmasq pushes the hostname to the DHCP client, but Win98 may ignore it — the guest-side Computer Name must still be set via registry.

### Bridge Setup with dnsmasq

If you choose to run dnsmasq on the bridge:

```bash
#!/usr/bin/env bash
set -euo pipefail

BRIDGE="loco-br"

# Create bridge (if not already done by entrypoint)
ip link add name "$BRIDGE" type bridge 2>/dev/null || true
ip addr add 192.168.10.1/24 dev "$BRIDGE" 2>/dev/null || true
ip link set "$BRIDGE" up

# Enable IP forwarding for NAT (if guests need internet)
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 ! -o "$BRIDGE" -j MASQUERADE

# Start dnsmasq with the loco-bridge config
dnsmasq --conf-file=/etc/dnsmasq.d/loco-bridge.conf --no-daemon &
DNSMASQ_PID=$!

echo "dnsmasq started (PID: $DNSMASQ_PID) on $BRIDGE"
```

### Kubernetes Deployment (Sidecar Pattern)

If dnsmasq is needed inside a Kubernetes pod, add it as a sidecar container with `NET_ADMIN` capability:

```yaml
- name: dhcp-server
  image: alpine:3.19
  command: ["sh", "-c", "apk add --no-cache dnsmasq && dnsmasq --conf-file=/etc/dnsmasq.d/loco-bridge.conf --no-daemon"]
  securityContext:
    capabilities:
      add: ["NET_ADMIN"]
  volumeMounts:
    - name: dnsmasq-config
      mountPath: /etc/dnsmasq.d/
```

## Verification

To confirm DHCP collision prevention is not needed (static IP scheme is active):

```bash
# Inside a running emulator pod:
# 1. Check that the entrypoint derived a unique IP
echo $GUEST_IP   # should be 192.168.10.(10+N)

# 2. Verify QEMU NIC has the correct MAC
echo $GUEST_MAC  # should be 52:54:00:10:00:0N

# 3. No dnsmasq process should be running (static IP mode)
pgrep dnsmasq && echo "WARNING: dnsmasq running — check if intentional" || echo "OK: no DHCP server (static IPs)"

# 4. Ping another instance to confirm connectivity
ping -c 1 192.168.10.11  # from instance 0 → instance 1
```

## Cross-References

- **L2**: [instance-identity-spec.md](instance-identity-spec.md) — static IP scheme definition
- **L6**: [network-topology.md](network-topology.md) — bridge/TAP architecture
- **E4**: `docs/knowledge/emulation/qemu-hardware-reference.md` — QEMU NIC/MAC config
- **Entrypoints**: `containers/qemu-softgpu/entrypoint.sh`, `containers/qemu/entrypoint.sh` — identity derivation
