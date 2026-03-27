# Lego Loco Game Navigation Map

**Date**: 2025-01-24
**Author**: @win98-lead
**Task**: W3
**Status**: finding

## Summary
Menu tree and navigation paths for Lego Loco within the Windows 98 guest OS.

## Startup Sequence
1. Desktop → Double-click "LEGO Loco" icon (or Start → Programs → LEGO Media → LEGO Loco)
2. Game launches → Intro video plays (skip with Esc or mouse click)
3. Main menu appears

## Main Menu
```
LEGO Loco Main Menu
├── Play (single player)
│   ├── New Town
│   ├── Load Town
│   └── Tutorial
├── Multiplayer
│   ├── Host Game
│   │   ├── Select Map/Town
│   │   └── Wait for Players
│   └── Join Game
│       ├── Browse Network Games (DirectPlay discovery)
│       └── Select Game → Join
├── Options
│   ├── Sound Volume
│   ├── Music Volume
│   └── Display Settings
└── Exit
```

## Multiplayer Flow (Critical for LAN testing)

### Host Instance (Instance 0 by convention)
1. Main Menu → Multiplayer → Host Game
2. Select map/town
3. Game starts listening on port 2300 (TCP/UDP) and 47624 (DirectPlay discovery)
4. Wait for other players to join

### Join Instance (Instances 1-8)
1. Main Menu → Multiplayer → Join Game
2. Game sends DirectPlay discovery broadcast on port 47624
3. Available games appear in list
4. Select host game → click Join
5. Game connects via TCP/UDP port 2300

### Verification
- Host should show player count increasing
- Joining player should see the host's town loading
- Both players should be able to build and see each other's changes

## Windows Navigation Quick Reference
| Action | Path |
|--------|------|
| IP config | Start → Run → `winipcfg` |
| Ping test | Start → Run → `command` → `ping 192.168.10.XX` |
| Network setup | Control Panel → Network → TCP/IP Properties |
| Device Manager | Control Panel → System → Device Manager tab |
| Computer name | Control Panel → Network → Identification tab |
| Network Neighborhood | Desktop → Network Neighborhood icon |
