<!-- living-document -->
# LAN Blockers Tracker

**Last Updated**: 2025-01-24
**Owner**: @lan-lead

This is a living document tracking all known blockers for LAN multiplayer functionality.

## Blocker Status

| # | Blocker | Status | Owner | Resolution Path | Depends |
|---|---------|--------|-------|-----------------|---------|
| 1 | Unique initial network config per instance (hostname, IP, computer name) | ❌ Open | @lan-lead, @win98-lead | Design identity spec (L2), implement per-instance config (W4) | — |
| 2 | Network join sequence undefined (which instance hosts, which joins) | ❌ Open | @lan-lead | Document join sequence (L4), requires game nav map (W3) | W3 |
| 3 | Port 2300 reachability between pods unverified | ❌ Open | @lan-lead, @k8s-lead | Add K8s test (L3), requires 9 pods running (K2) | K2 |
| 4 | NetBIOS name resolution across instances untested | ❌ Open | @lan-lead | Test Network Neighborhood (L5), requires unique config (L2, W4) | L2, W4 |
| 5 | DHCP collision prevention with 9 instances | ❌ Open | @lan-lead | Verify/implement unique DHCP leases (L7), requires identity spec (L2) | L2 |
| 6 | TAP interface creation in Kind/minikube (NET_ADMIN capability) | ❌ Open | @emulation-lead, @k8s-lead | Verify TAP in Kind (E2), requires 9 replicas (K2) | K2 |
| 7 | Game discovery broadcast reaching all instances | ❌ Open | @lan-lead | Test broadcast scope, may need directed discovery | L3 |

## Resolution Log

*No blockers resolved yet. This section will be updated as blockers are addressed.*

## Cross-Team Dependencies
- **@emulation-lead**: QEMU ne2k_pci NIC configuration, TAP interface creation
- **@k8s-lead**: NetworkPolicy for ports 2300/47624, pod networking, NET_ADMIN
- **@win98-lead**: Guest OS TCP/IP config, hostname/computer name setting
- **@qa-lead**: LAN multiplayer E2E test (Q1)
