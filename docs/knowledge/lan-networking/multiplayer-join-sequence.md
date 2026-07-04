# Lego Loco Multiplayer Join Sequence

**Date**: 2026-03-27
**Author**: @lan-lead
**Task**: L4
**Status**: spec

## Summary

Step-by-step procedure for establishing a Lego Loco multiplayer session across the 9 QEMU Windows 98 instances in the cluster. Instance 0 (`LOCO-00`, `192.168.10.10`) is the designated game host. Instances 1–8 join as clients.

---

## Prerequisites

Before attempting a multiplayer session, verify:

- [ ] All instances are running and booted to the Windows 98 desktop
- [ ] Each instance has its unique network identity configured (see [Instance Identity Spec](instance-identity-spec.md))
- [ ] Instances can ping each other: `ping 192.168.10.10` from any client
- [ ] Network Neighborhood shows at least the host (`LOCO-00`) on each client
- [ ] Lego Loco is installed and launchable on all instances (see [Snapshot Variants](../win98-image/snapshot-variants.md))
- [ ] TCP port 2300 and UDP port 2300 are reachable between all pods (see [Network Topology](network-topology.md))
- [ ] DirectPlay TCP/IP service provider is registered (`dxdiag` → DirectPlay tab)

---

## Network Ports Required

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 2300 | TCP | Host ↔ Clients | DirectPlay game data |
| 2300 | UDP | Host ↔ Clients | DirectPlay game data |
| 47624 | TCP | Clients → Host | DirectPlay session discovery |
| 137–139 | TCP/UDP | All ↔ All | NetBIOS name resolution (optional but helps) |

Ensure the Kubernetes NetworkPolicy allows this traffic between emulator pods. See `k8s/networkpolicy-game-ports.yaml`.

---

## Step-by-Step Join Sequence

### Step 1: Verify Host Instance (LOCO-00)

| Field | Value |
|-------|-------|
| Instance Index | 0 |
| IP Address | 192.168.10.10 |
| Hostname | LOCO-00 |
| MAC Address | 52:54:00:10:00:00 |
| Role | **Game Host (Server)** |

Confirm the host is ready:
1. Open a DOS prompt: Start → Run → `command`
2. Run `winipcfg` — verify IP is `192.168.10.10`
3. Run `ping 192.168.10.11` — verify at least one client responds

### Step 2: Host Creates a Game Session

On **LOCO-00** (Instance 0):

1. Launch Lego Loco (desktop shortcut or Start → Programs → LEGO Media → LEGO Loco)
2. Skip the intro video (Esc or mouse click)
3. At the Main Menu, click **Multiplayer**
4. Click **Host Game**
5. When prompted for session name, enter: **`LOCO-PARTY`**
6. Select a town/map (or create a new one)
7. The game begins listening for incoming connections:
   - TCP port 2300 (game data)
   - TCP port 47624 (session advertisement / discovery)
8. The host screen shows "Waiting for players..." or equivalent lobby view

**DirectPlay Session Name Convention**: `LOCO-PARTY`
- All automation and test scripts should search for this exact session name
- If running multiple independent sessions, use `LOCO-PARTY-{group_id}`

### Step 3: Clients Join the Session

On each client instance (**LOCO-01** through **LOCO-08**, one at a time):

1. Launch Lego Loco
2. Skip the intro video
3. At the Main Menu, click **Multiplayer**
4. Click **Join Game**
5. The game sends a DirectPlay discovery query to the local network:
   - Broadcasts on UDP to find sessions
   - Also queries TCP port 47624 on known hosts
6. A list of available sessions appears — look for **"LOCO-PARTY"**
7. Select **"LOCO-PARTY"** in the session list
8. Click **Connect** (or **Join**)
9. Wait for connection to establish — the host's town begins loading on the client

**Join order**: Join clients one at a time (LOCO-01, then LOCO-02, etc.) to avoid overwhelming the host. Wait for each client to fully load before joining the next.

### Step 4: Verify All Players Connected

After all clients have joined:

1. **On the host (LOCO-00)**: Verify player count matches expected number
2. **On each client**: Verify the host's town is visible and interactive
3. **Interaction test**: Have one instance place a building/track piece — verify it appears on other instances
4. **Latency check**: Actions should propagate within 1–2 seconds on a local bridge network

### Step 5: Gameplay Verification

| Check | Expected Result |
|-------|----------------|
| Player count on host | N+1 (host + N clients) |
| Town loads on clients | Host's map visible | 
| Build actions sync | Placing a track piece visible to all |
| Chat/interaction | Player avatars visible |
| No disconnects after 60s | All sessions stable |

---

## DirectPlay Protocol Details

Lego Loco uses **DirectPlay 6** (part of DirectX 6.1) for multiplayer:

- **Service Provider**: TCP/IP (not IPX/SPX)
- **Session Discovery**: The client broadcasts a DirectPlay enumeration request. The host responds with session information (name, player count, etc.)
- **Connection**: Once a session is selected, the client establishes a TCP connection to the host on port 2300
- **Data Transfer**: Game state synchronization uses both TCP (reliable) and UDP (fast updates) on port 2300
- **Session Name**: Set by the host at creation time — must match exactly when searching

### Port Allocation
DirectPlay may allocate additional ports dynamically in the range 2300–2400. The primary ports are:
- **2300 TCP/UDP**: Game session data
- **47624 TCP**: Session discovery and enumeration

---

## Failure Recovery

### Session Not Appearing in Browse List

| Check | Command / Action | Expected |
|-------|-----------------|----------|
| Host is running? | VNC into LOCO-00, verify game is in lobby | Lobby screen visible |
| Network reachable? | On client: `ping 192.168.10.10` | Reply from host |
| Port 2300 open? | On client: (no netstat in Win98) — use test pod | Connection accepted |
| Port 47624 open? | k8s-test: `nc -z 192.168.10.10 47624` | Connection accepted |
| DirectPlay registered? | On client: `dxdiag` → DirectPlay | TCP/IP listed |
| Firewall? | Win98 has no built-in firewall | N/A |
| NetworkPolicy? | `kubectl get networkpolicy -n loco` | Game ports allowed |
| Same subnet? | `winipcfg` on both instances | Both on 192.168.10.x/24 |

### Connection Drops During Game

1. Check if the host instance (LOCO-00) is still running: VNC into it
2. Check if the QEMU process is alive: `kubectl logs loco-emulator-0 -n loco`
3. If host crashed, all clients lose connection — restart host and have all clients rejoin
4. If a single client dropped, that client can rejoin without affecting others

### Client Stuck on "Connecting..."

1. Wait 30 seconds — DirectPlay has a long timeout
2. If still stuck, press Esc to cancel and retry
3. Verify Network Neighborhood shows the host: double-click Network Neighborhood on the desktop
4. If Network Neighborhood is empty, run `nbtstat -R` in DOS prompt to clear the NetBIOS cache, then wait 1–2 minutes

### Host Cannot Create Session

1. Verify DirectPlay TCP/IP is installed: `dxdiag` → DirectPlay tab
2. Re-run DirectX setup from the Lego Loco CD if DirectPlay is missing
3. Check that no other DirectPlay application is using port 2300
4. Revert to `multiplayer-ready` snapshot and retry

---

## Automation Notes

For automated testing (Playwright, k8s-tests):

1. **VNC automation**: Use noVNC or direct VNC to control mouse/keyboard on each instance
2. **Click coordinates**: Menu items have fixed positions at 1024×768 resolution
3. **Session enumeration timing**: Allow 5–10 seconds between host creation and client browse
4. **Verification**: Check for session name text on screen (OCR or pixel matching)
5. **Test script reference**: See `k8s-tests/test-broadcast.sh` for network-level DirectPlay port testing

---

## References

- [Instance Identity Spec](instance-identity-spec.md) — IP, hostname, MAC per instance
- [Network Topology](network-topology.md) — bridge, TAP, pod architecture
- [Game Navigation Map](../win98-image/game-navigation-map.md) — full menu tree
- [Snapshot Variants](../win98-image/snapshot-variants.md) — `multiplayer-ready` snapshot definition
- `k8s/networkpolicy-game-ports.yaml` — Kubernetes network policy for game ports
