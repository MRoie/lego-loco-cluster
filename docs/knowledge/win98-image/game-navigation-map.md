# Lego Loco Game Navigation Map

**Date**: 2026-03-27
**Author**: @win98-lead
**Task**: W3
**Status**: finding

## Summary

Complete menu tree and navigation paths for Lego Loco within the Windows 98 guest OS, from desktop launch through multiplayer session setup. This document is the reference for VNC automation click targets and test verification.

---

## Desktop Shortcut Path

| Method | Path |
|--------|------|
| Desktop icon | Double-click **"LEGO Loco"** shortcut on Desktop |
| Start Menu | Start → Programs → LEGO Media → **LEGO Loco** |
| File system | `C:\Program Files\LEGO Media\LEGO Loco\LegoLoco.exe` |
| CD Autorun | Insert Lego Loco CD → Autorun launches installer/game |

The desktop shortcut is the preferred launch method for automation (fixed icon position).

---

## Game Startup Sequence

```
1. User double-clicks "LEGO Loco" icon
   │
2. CD Check — game verifies Lego Loco CD is mounted
   │  ├── CD found → proceed
   │  └── CD not found → "Please insert the Lego Loco CD" dialog
   │     └── Ensure QEMU has ISO mounted: -cdrom /path/to/legoloco.iso
   │
3. Lego Loco executable launches (LegoLoco.exe)
   │
4. Intro video plays (Lego Media splash, game intro cinematic)
   │  └── Skip: press Esc or click mouse
   │
5. Main Menu appears
```

### CD Check Details
- The game checks for `D:\` (or whatever drive letter QEMU assigns to -cdrom)
- QEMU flag: `-cdrom /data/legoloco.iso` ensures the ISO is always available
- If the CD check fails on every boot, the CD-ROM driver may need reinstalling in Device Manager

### Autorun Behavior
- If Windows 98 Autorun is enabled and the ISO is first mounted, it triggers the Lego Loco installer
- On already-installed systems, Autorun may open the game launcher or do nothing
- Autorun can be disabled: hold Shift while mounting, or disable via registry (`HKLM\SYSTEM\CurrentControlSet\Services\Cdrom` → `Autorun` = 0)

---

## Main Menu Tree

```
LEGO Loco Main Menu
│
├── Play (Single Player)
│   ├── New Town         → Start a fresh town with empty landscape
│   ├── Load Town        → Browse saved towns (C:\Program Files\LEGO Media\LEGO Loco\SaveData\)
│   └── Tutorial         → Guided introduction to building
│
├── Multiplayer
│   ├── Host Game
│   │   ├── Enter Session Name (default: computer name, use "LOCO-PARTY")
│   │   ├── Select Town (New or Load existing)
│   │   └── Wait for Players (lobby — players appear as they connect)
│   │
│   └── Join Game
│       ├── Browse Sessions (DirectPlay TCP/IP enumeration)
│       │   └── Session list shows: Name, Host, Player Count
│       ├── Select Session → click "LOCO-PARTY"
│       └── Connect → loads host's town on client
│
├── Options
│   ├── Sound Volume     → slider (0–100%)
│   ├── Music Volume     → slider (0–100%)
│   └── Display Settings → resolution, color depth (managed by SoftGPU driver)
│
└── Exit                 → Returns to Windows 98 desktop
```

---

## Multiplayer Flow (Critical for LAN Testing)

### Host Game Flow (Instance 0 — LOCO-00)

```
Main Menu
  → Multiplayer
    → Host Game
      → Session Name: "LOCO-PARTY"    ← DirectPlay session name
      → Select town (New Town or Load)
      → Lobby screen: "Waiting for players..."
         ├── Port 2300 TCP/UDP now listening (game data)
         ├── Port 47624 TCP now listening (session discovery)
         └── Player list updates as clients join
```

### Join Game Flow (Instances 1–8)

```
Main Menu
  → Multiplayer
    → Join Game
      → Browse Sessions
         ├── DirectPlay sends UDP broadcast for discovery
         ├── Also queries TCP port 47624 on subnet
         └── Session list populates (may take 3–10 seconds)
      → Select "LOCO-PARTY" from list
      → Click Connect/Join
         ├── TCP connection to host on port 2300
         └── Host's town loads on client screen
```

### DirectPlay Session Name Convention

| Field | Value |
|-------|-------|
| Session Name | `LOCO-PARTY` |
| Service Provider | TCP/IP for DirectPlay |
| Host Port | 2300 (TCP/UDP) |
| Discovery Port | 47624 (TCP) |
| Max Players | Limited by Lego Loco (typically 2–8) |

All automation scripts and test harnesses should search for the session name `LOCO-PARTY`. For multiple independent test groups, use `LOCO-PARTY-{group_id}`.

### Verification Checklist
- [ ] Host shows lobby with "Waiting for players"
- [ ] Client browse list shows "LOCO-PARTY" session
- [ ] Client successfully loads host's town
- [ ] Player count on host increments per join
- [ ] Both players can place building pieces and see each other's changes
- [ ] No disconnects after 60 seconds of idle

---

## In-Game Controls Overview

### Mouse Controls (Primary)
| Action | Control |
|--------|---------|
| Select / Place | Left click |
| Cancel / Deselect | Right click |
| Scroll map | Click and drag on map edges, or arrow keys |
| Zoom | Mouse wheel (if supported) or +/- keys |
| Open toolbox | Click toolbox icon (bottom of screen) |

### Keyboard Controls
| Key | Action |
|-----|--------|
| Esc | Open pause menu / cancel current action |
| F1 | Help |
| Arrow keys | Scroll/pan the map |
| Space | Pause/resume simulation |
| Ctrl+S | Quick save (if supported) |

### Toolbox Categories
- **Track pieces** — Lay train tracks (straight, curved, junction)
- **Buildings** — Place houses, stations, shops
- **Scenery** — Trees, fences, decorations
- **People** — Place Lego minifigures
- **Trains** — Select and deploy train engines

---

## Save / Load Paths

### Save Data Location
```
C:\Program Files\LEGO Media\LEGO Loco\SaveData\
```

### Save File Format
- Files: `*.sav` or game-specific binary format
- Named by town name entered during save

### Save (Single Player)
1. Press **Esc** or click the **Menu** button in-game
2. Select **Save Town**
3. Enter a name for the town
4. Click **Save**

### Load (Single Player)
1. From Main Menu → **Play** → **Load Town**
2. Or in-game: Esc → **Load Town**
3. Browse saved towns
4. Select and click **Load**

### Multiplayer Save
- Only the **host** can save the multiplayer town
- Saved multiplayer towns can be loaded later for single-player or as a new multiplayer session
- Clients do not retain a local copy of the multiplayer town

### Backup Strategy
- Save data persists in the QCOW2 disk image
- Snapshot `multiplayer-ready` does NOT include save data from gameplay sessions
- To preserve a played town, take a new snapshot after saving: `savevm post-session-01`

---

## Windows Navigation Quick Reference

| Action | Path |
|--------|------|
| Launch game | Desktop → "LEGO Loco" icon (double-click) |
| IP config | Start → Run → `winipcfg` |
| Ping test | Start → Run → `command` → `ping 192.168.10.XX` |
| Network setup | Start → Settings → Control Panel → Network → TCP/IP → Properties |
| Device Manager | Start → Settings → Control Panel → System → Device Manager tab |
| Computer name | Start → Settings → Control Panel → Network → Identification tab |
| Network Neighborhood | Desktop → Network Neighborhood icon |
| DirectPlay check | Start → Run → `dxdiag` → DirectPlay tab |
| DOS prompt | Start → Programs → MS-DOS Prompt (or Start → Run → `command`) |
| Shut down | Start → Shut Down → "Shut down the computer" |

---

## References

- [Multiplayer Join Sequence](../lan-networking/multiplayer-join-sequence.md) — detailed step-by-step join procedure
- [Instance Identity Spec](../lan-networking/instance-identity-spec.md) — per-instance IP, hostname, MAC
- [Snapshot Variants](snapshot-variants.md) — QCOW2 snapshot chain
- [Shutdown/Restart Procedures](shutdown-restart.md) — safe guest operations
