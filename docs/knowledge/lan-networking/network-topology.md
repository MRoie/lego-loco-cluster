# Network Topology

**Date**: 2025-01-24
**Author**: @lan-lead
**Task**: L6
**Status**: finding

## Summary
Reference diagram for the Lego Loco Cluster network architecture.

## Topology

```
┌─────────────────────────────────────────────────────┐
│                 Kubernetes Cluster                    │
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │            loco-br (bridge)                   │    │
│  │            192.168.10.1/24                    │    │
│  │                                               │    │
│  │  ┌─────┐ ┌─────┐ ┌─────┐     ┌─────┐        │    │
│  │  │tap0 │ │tap1 │ │tap2 │ ... │tap8 │        │    │
│  │  └──┬──┘ └──┬──┘ └──┬──┘     └──┬──┘        │    │
│  └─────┼───────┼───────┼──────────┼────────────┘    │
│        │       │       │          │                   │
│  ┌─────┴──┐┌───┴───┐┌──┴────┐ ┌──┴────┐             │
│  │QEMU-0  ││QEMU-1 ││QEMU-2 │ │QEMU-8 │             │
│  │ne2k_pci││ne2k_pci││ne2k_pci│ │ne2k_pci│            │
│  │.10.10  ││.10.11  ││.10.12  │ │.10.18  │            │
│  │VNC:5900││VNC:5901││VNC:5902│ │VNC:5908│            │
│  └────────┘└────────┘└────────┘ └────────┘            │
│                                                       │
│  ┌───────────┐  ┌────────────┐                       │
│  │ Backend   │  │ Frontend   │                       │
│  │ :3000     │  │ :80        │                       │
│  │ WebSocket │  │ React+VR   │                       │
│  └───────────┘  └────────────┘                       │
└─────────────────────────────────────────────────────┘
```

## Port Map
| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| VNC | 5900-5908 | TCP | QEMU display per instance |
| WebRTC | 8080-8088 | UDP/TCP | Video stream per instance |
| Audio | 5001 | UDP | GStreamer audio output |
| DirectPlay | 2300 | TCP/UDP | Lego Loco game traffic |
| DirectPlay | 47624 | TCP | Game session discovery |
| NetBIOS | 137-139 | TCP/UDP | Name service, sessions |
| Backend | 3000 | TCP | Express API + WebSocket |
| Frontend | 80 | TCP | Nginx serving React app |

## IP Assignment Scheme
Instances use static IPs on the 192.168.10.0/24 subnet:
- Bridge gateway: 192.168.10.1
- Instance N: 192.168.10.(10 + N) where N = 0-8
- Example: Instance 3 → 192.168.10.13, hostname LOCO-03
