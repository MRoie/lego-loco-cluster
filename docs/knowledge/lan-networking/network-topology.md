# Network Topology

**Date**: 2026-03-27
**Author**: @lan-lead
**Task**: L6
**Status**: finding

## Summary
Reference diagram for the Lego Loco Cluster network architecture, including per-instance identity, Kubernetes networking, and Kind-specific notes.

## Topology

```
┌───────────────────────────────────────────────────────────────────────┐
│                       Kubernetes Cluster (Kind / Minikube)            │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │              loco-br (Linux bridge, 192.168.10.1/24)          │    │
│  │                                                               │    │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐     ┌─────┐               │    │
│  │  │tap0 │ │tap1 │ │tap2 │ │tap3 │ ... │tap8 │               │    │
│  │  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘     └──┬──┘               │    │
│  └─────┼───────┼───────┼───────┼──────────┼────────────────────┘    │
│        │       │       │       │          │                          │
│  ┌─────┴────┐┌─┴──────┐┌──┴──────┐  ┌──┴──────┐                    │
│  │ QEMU-0   ││ QEMU-1  ││ QEMU-2  │  │ QEMU-8  │                    │
│  │ LOCO-00  ││ LOCO-01  ││ LOCO-02  │  │ LOCO-08  │                   │
│  │ ne2k_pci ││ ne2k_pci ││ ne2k_pci │  │ ne2k_pci │                   │
│  │ .10.10   ││ .10.11   ││ .10.12   │  │ .10.18   │                   │
│  │ MAC:..00 ││ MAC:..01 ││ MAC:..02 │  │ MAC:..08 │                   │
│  │ VNC:5900 ││ VNC:5901 ││ VNC:5902 │  │ VNC:5908 │                   │
│  │ HOST⭐   ││ CLIENT   ││ CLIENT   │  │ CLIENT   │                   │
│  └──────────┘└─────────┘└─────────┘  └─────────┘                    │
│                                                                       │
│  ┌────────────┐  ┌─────────────┐  ┌──────────────────────┐          │
│  │ Backend    │  │ Frontend    │  │ NetworkPolicy        │          │
│  │ :3000      │  │ :80         │  │ Allow 2300, 47624    │          │
│  │ WebSocket  │  │ React + VR  │  │ Allow 137-139        │          │
│  │ REST API   │  │ NoVNC/WebRTC│  │ Between emulator pods│          │
│  └────────────┘  └─────────────┘  └──────────────────────┘          │
└───────────────────────────────────────────────────────────────────────┘
```

## Per-Instance Identity

Each QEMU instance has a deterministic identity derived from its index N (0–8). See [Instance Identity Spec](instance-identity-spec.md) for full details.

| Index | IP Address | Hostname | MAC Address | TAP | VNC Port | Role |
|-------|-----------|----------|-------------|-----|----------|------|
| 0 | 192.168.10.10 | LOCO-00 | 52:54:00:10:00:00 | tap0 | 5900 | Game Host |
| 1 | 192.168.10.11 | LOCO-01 | 52:54:00:10:00:01 | tap1 | 5901 | Client |
| 2 | 192.168.10.12 | LOCO-02 | 52:54:00:10:00:02 | tap2 | 5902 | Client |
| 3 | 192.168.10.13 | LOCO-03 | 52:54:00:10:00:03 | tap3 | 5903 | Client |
| 4 | 192.168.10.14 | LOCO-04 | 52:54:00:10:00:04 | tap4 | 5904 | Client |
| 5 | 192.168.10.15 | LOCO-05 | 52:54:00:10:00:05 | tap5 | 5905 | Client |
| 6 | 192.168.10.16 | LOCO-06 | 52:54:00:10:00:06 | tap6 | 5906 | Client |
| 7 | 192.168.10.17 | LOCO-07 | 52:54:00:10:00:07 | tap7 | 5907 | Client |
| 8 | 192.168.10.18 | LOCO-08 | 52:54:00:10:00:08 | tap8 | 5908 | Client |

- **MAC prefix**: `52:54:00` (QEMU locally-administered OUI), `10:00:0N` unique per instance
- **Workgroup**: `LOCOLAND` (all instances)
- **Gateway**: `192.168.10.1` (loco-br bridge)

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

## NetworkPolicy

A Kubernetes NetworkPolicy (`k8s/networkpolicy-game-ports.yaml`) must allow the following traffic between emulator pods:

```yaml
# Required ingress/egress rules for game connectivity
- ports:
    - port: 2300       # DirectPlay game data
      protocol: TCP
    - port: 2300
      protocol: UDP
    - port: 47624      # DirectPlay session discovery
      protocol: TCP
    - port: 137        # NetBIOS Name Service
      protocol: UDP
    - port: 138        # NetBIOS Datagram
      protocol: UDP
    - port: 139        # NetBIOS Session
      protocol: TCP
  from/to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/component: emulator
```

**Key policy decisions**:
- Emulator-to-emulator traffic is allowed on game and NetBIOS ports
- Backend can reach emulator pods on VNC ports (5900–5908) for stream proxying
- Frontend does not directly access emulator pods — all traffic routes through Backend
- Egress to the internet is denied for emulator pods (Win98 guests don't need it)

## Kind-Specific Networking Notes

When running the cluster locally with **Kind** (Kubernetes in Docker):

### TAP/Bridge Creation
- TAP interfaces require `NET_ADMIN` capability on the container
- Kind nodes run as Docker containers, so the pod's TAP/bridge live inside Docker's network namespace
- Add to the pod security context:
  ```yaml
  securityContext:
    capabilities:
      add: ["NET_ADMIN", "NET_RAW"]
  ```

### Port Exposure
- Kind does not expose NodePorts by default — configure `extraPortMappings` in `kind-config.yaml`:
  ```yaml
  nodes:
    - role: control-plane
      extraPortMappings:
        - containerPort: 30080   # Frontend NodePort
          hostPort: 80
        - containerPort: 30000   # Backend NodePort
          hostPort: 3000
  ```
- VNC ports (5900–5908) are accessed through the Backend proxy, not directly exposed

### Bridge Networking Inside Kind
- Each Kind node has its own network namespace — the `loco-br` bridge is created per-pod, not per-node
- All 9 QEMU instances should run on the **same node** to share the bridge, or use a CNI plugin that supports L2 bridging across nodes
- For single-node Kind clusters (recommended for dev): all pods share the node, and the bridge connects all TAP interfaces

### DNS and Service Discovery
- Kind uses CoreDNS — pod-to-pod DNS works via `<pod-name>.<service-name>.<namespace>.svc.cluster.local`
- However, Win98 guests use NetBIOS name resolution, not DNS — ensure the bridge allows broadcast traffic
- The bridge `loco-br` must have `bridge-nf-call-iptables` disabled to allow broadcast frames:
  ```bash
  echo 0 > /proc/sys/net/bridge/bridge-nf-call-iptables
  ```

### Known Kind Limitations
| Issue | Workaround |
|-------|-----------|
| No GPU passthrough | Use SoftGPU (software rendering) |
| Limited CPU for 9 QEMU instances | Allocate ≥4 cores to Docker Desktop |
| Slow disk I/O for QCOW2 | Use tmpfs or SSD-backed volume |
| Bridge broadcast filtering | Disable bridge-nf-call-iptables |

---

## References

- [Instance Identity Spec](instance-identity-spec.md) — full identity derivation and injection pipeline
- [Multiplayer Join Sequence](multiplayer-join-sequence.md) — step-by-step game session setup
- `k8s/networkpolicy-game-ports.yaml` — NetworkPolicy manifest
- `k8s/kind-config.yaml` — Kind cluster configuration
