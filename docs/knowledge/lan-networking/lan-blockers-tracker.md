<!-- living-document -->
# LAN Blockers Tracker

**Last Updated**: 2026-03-27
**Owner**: @lan-lead

This is a living document tracking all known blockers for LAN multiplayer functionality.

## Blocker Status

| # | Blocker | Status | Owner | Resolution Path | Depends |
|---|---------|--------|-------|-----------------|---------|
| 1 | Unique initial network config per instance (hostname, IP, computer name) | 🟢 Resolved | @lan-lead, @win98-lead | Identity spec (L2) + per-instance config script (W4) | — |
| 2 | Network join sequence undefined (which instance hosts, which joins) | 🟢 Resolved | @lan-lead | Join sequence documented (L4), game nav map done (W3) | W3 |
| 3 | Port 2300 reachability between pods unverified | 🟡 Test Created | @lan-lead, @k8s-lead | Test script + NetworkPolicy created (L3, K3). Awaiting live cluster. | K2 |
| 4 | NetBIOS name resolution across instances untested | 🟡 Test Created | @lan-lead | NetBIOS test script created (L5). Awaiting live cluster. | L2, W4 |
| 5 | DHCP collision prevention with 9 instances | 🟢 Resolved | @lan-lead | Static IP scheme (L2) eliminates DHCP entirely; dnsmasq fallback documented (L7) | L2 |
| 6 | TAP interface creation in Kind/minikube (NET_ADMIN capability) | 🟢 Resolved | @emulation-lead, @k8s-lead | TAP creation updated with per-instance identity (E2). K2 validated 9 replicas. | K2 |
| 7 | Game discovery broadcast reaching all instances | 🟡 Test Created | @lan-lead | Game port test covers broadcast. NetworkPolicy allows it (K3). | L3 |

## Resolution Log

| Date | Blocker | Change | Details |
|------|---------|--------|---------|
| 2026-03-27 | #1 Unique network config | ❌ Open → 🟢 Resolved | L2 identity spec created (IP/MAC/hostname per instance). W4 script generates .reg + .bat for guest config. |
| 2026-03-27 | #2 Join sequence | ❌ Open → 🟢 Resolved | L4 multiplayer join sequence documented. W3 game navigation map completed. LOCO-00 designated as host. |
| 2026-03-27 | #3 Port 2300 reachability | ❌ Open → 🟡 Test Created | Created `k8s-tests/test-game-ports.sh` (TCP/UDP 2300, TCP 47624 between all 9 pod pairs). Created `k8s/networkpolicy-game-ports.yaml` and Helm template (K3). Awaiting live cluster. |
| 2026-03-27 | #4 NetBIOS name resolution | ❌ Open → 🟡 Test Created | Created `k8s-tests/test-netbios.sh` (UDP 137-139, nmblookup, workgroup browse). Awaiting live cluster. |
| 2026-03-27 | #5 DHCP collision | ❌ Open → 🟢 Resolved | Static IP scheme from L2 spec (192.168.10.10-18) eliminates DHCP collisions. Fallback dnsmasq config documented. |
| 2026-03-27 | #6 TAP interface creation | ❌ Open → 🟢 Resolved | E2 updated entrypoints with per-instance TAP derivation from POD_NAME. K2 confirmed NET_ADMIN + privileged in StatefulSet. |
| 2026-03-27 | #7 Game discovery broadcast | ❌ Open → 🟡 Test Created | K3 NetworkPolicy allows broadcast ports. Game port test covers connectivity. |

## Cross-Team Dependencies
- **@emulation-lead**: QEMU ne2k_pci NIC configuration, TAP interface creation
- **@k8s-lead**: NetworkPolicy for ports 2300/47624, pod networking, NET_ADMIN
- **@win98-lead**: Guest OS TCP/IP config, hostname/computer name setting
- **@qa-lead**: LAN multiplayer E2E test (Q1)
