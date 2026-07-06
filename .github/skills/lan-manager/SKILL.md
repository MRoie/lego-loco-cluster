---
name: lan-manager
description: 'LAN networking and multiplayer for Lego Loco Cluster. Covers TAP/bridge config, per-instance IP assignment, DirectPlay port 2300/47624, NetBIOS discovery, DHCP management, and LAN party orchestration.'
---

# LAN Manager Skill

## When to Use
- TAP interface or bridge network configuration
- Per-instance IP/hostname assignment
- DirectPlay multiplayer connectivity
- Port 2300/47624 testing
- NetBIOS/WINS name resolution
- DHCP collision prevention

## Network Architecture
- Bridge: loco-br at 192.168.10.1/24
- TAP: tap0-tap8, IPs: 192.168.10.10-18
- NIC: ne2k_pci (RTL8029AS)
- Game: TCP/UDP 2300, DirectPlay 47624
- NetBIOS: ports 137-139

## Known Blockers (7)
1. Unique network config per instance
2. Join sequence undefined
3. Port 2300 unverified
4. NetBIOS untested
5. DHCP collision risk
6. TAP needs NET_ADMIN in Kind
7. Broadcast scope unknown

## Key Files
- `containers/qemu/entrypoint.sh` — TAP setup
- `scripts/setup_bridge.sh` — bridge creation
- `k8s-tests/test-network.sh`, `test-tcp.sh`, `test-broadcast.sh`

## Procedure
1. Review bridge/TAP setup in entrypoints
2. Check `docs/knowledge/lan-networking/` for prior findings
3. Test connectivity between instances
4. Verify game port reachability
5. Document in `docs/knowledge/lan-networking/<date>-<topic>.md`

## Tasks: L1 (blocker tracker P0), L2 (network identity P0), L3 (port 2300 P0), L4 (join sequence), L5 (NetBIOS), L6 (topology diagram), L7 (DHCP)
