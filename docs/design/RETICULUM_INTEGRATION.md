# Reticulum Network Integration for Win98 Pod Communication

## Overview

This document describes the integration of [Reticulum](https://reticulum.network/) as an
encrypted mesh-networking layer between the Windows 98 emulator pods in the Lego
Loco cluster.  Reticulum provides transport-independent, end-to-end encrypted
communication over any mix of TCP, UDP, I2P, LoRa, serial, or pipe-based links.
Its lightweight footprint and auto-interface discovery make it well suited for a
cluster of QEMU-emulated guests that currently rely on noVNC and GStreamer for
video/audio but lack a dedicated game-state synchronisation channel.

## Goals

| # | Goal | Success Metric |
|---|------|----------------|
| 1 | Encrypted pod-to-pod messaging | All 9 pods can exchange payloads over Reticulum |
| 2 | Game-state synchronisation | Train positions and scene state replicated in <50 ms |
| 3 | Zero-config mesh discovery | Pods auto-discover neighbours without manual config |
| 4 | Minimal resource overhead | <10 MB RAM and <1 % CPU per pod sidecar |
| 5 | WASM portability path | Demonstrate Reticulum primitives compiled to WASM |

## Architecture

### Current Communication Model

```
┌─────────────┐    WebRTC / noVNC     ┌──────────────┐
│  Browser UI  │◄────────────────────►│  Emulator Pod │
└──────┬──────┘                       └──────┬───────┘
       │ WebSocket                           │ (no direct
       ▼                                     │  pod-to-pod
┌─────────────┐   K8s API discovery          │  data path)
│   Backend    │◄────────────────────────────►│
└─────────────┘                              ▼
                                      ┌──────────────┐
                                      │  Emulator Pod │
                                      │   (isolated)  │
                                      └──────────────┘
```

Today each emulator pod communicates **only** with the backend (for health) and
the browser (for streaming).  There is no direct data channel between pods.

### Proposed Reticulum Overlay

```
┌──────────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                      │
│                                                          │
│  ┌────────────┐   Reticulum AutoInterface   ┌──────────┐│
│  │ Pod 0      │◄───────────────────────────►│ Pod 1     ││
│  │ ┌────────┐ │   (UDP multicast on         │┌────────┐ ││
│  │ │ QEMU   │ │    loco-network bridge)     ││ QEMU   │ ││
│  │ └───┬────┘ │                             │└───┬────┘ ││
│  │     │ QMP  │                             │    │ QMP  ││
│  │ ┌───▼────┐ │                             │┌───▼────┐ ││
│  │ │Ret.    │ │   rnstransport link         ││Ret.    │ ││
│  │ │Sidecar │◄├─────────────────────────────┤│Sidecar │ ││
│  │ └────────┘ │                             │└────────┘ ││
│  └─────┬──────┘                             └─────┬─────┘│
│        │               ...                        │      │
│        │         ┌──────────┐                     │      │
│        └────────►│ Pod 8    │◄────────────────────┘      │
│                  │ Ret.Side │                             │
│                  └──────────┘                             │
│                                                          │
│  ┌─────────────┐         ┌─────────────┐                 │
│  │  Backend    │────────►│  Ret. Hub   │  (optional)     │
│  └─────────────┘         └─────────────┘                 │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

Each emulator pod gains a **Reticulum sidecar** container that:

1. Runs the `rnsd` (Reticulum Network Stack Daemon).
2. Uses the `AutoInterface` bound to the existing `loco-network` bridge
   (`172.20.0.0/16`).
3. Exposes a local Unix-domain or TCP socket so that game-state relay
   processes inside the container can send/receive Reticulum messages.

### Interface Configuration

Per the [Reticulum Auto Interface documentation](https://reticulum.network/manual/interfaces.html#interfaces-auto):

```ini
# /etc/reticulum/config  (inside each sidecar)
[reticulum]
  enable_transport = True
  share_instance   = Yes
  instance_control_port = 37428

[interfaces]
  [[Default Interface]]
    type = AutoInterface
    enabled = True

    # Optional: constrain discovery to the loco-network bridge
    group_id = 6c6f636f     # "loco" in hex
    discovery_scope = link  # limit to L2 segment

  [[TCP Server Interface]]
    type = TCPServerInterface
    enabled = True
    listen_ip = 0.0.0.0
    listen_port = 4242
```

The `AutoInterface` automatically discovers other Reticulum instances on the
same Layer-2 segment via IPv6 link-local multicast.  Because all emulator pods
share the `loco-network` Docker bridge, no manual peer configuration is needed.

## Data Flow Diagrams

### 1. Pod Discovery (Mesh Formation)

```
                    Time ──────────────────────────►

Pod-0 rnsd         Pod-1 rnsd         Pod-2 rnsd
   │                  │                  │
   │──► AutoInterface │                  │
   │    announce()    │                  │
   │    (multicast)   │                  │
   │                  │──► receive       │
   │                  │    announce      │
   │                  │──► add peer      │
   │                  │                  │──► receive
   │                  │                  │    announce
   │                  │                  │──► add peer
   │                  │                  │
   │◄── announce ─────│                  │
   │    add peer      │                  │
   │                  │◄── announce ─────│
   │                  │    add peer      │
   │◄── announce ────────────────────────│
   │    add peer      │                  │
   │                  │                  │
   ▼                  ▼                  ▼
  Full mesh established (all 3 peers known)
```

### 2. Game-State Synchronisation

```
┌──────────┐        ┌──────────────┐        ┌──────────┐
│  Win98   │  QMP   │  Reticulum   │  RNS   │ Reticulum│
│  Guest   │◄──────►│  Sidecar     │◄──────►│ Sidecar  │
│ (Pod 0)  │        │  (Pod 0)     │ Link   │ (Pod 1)  │
└──────────┘        └──────────────┘        └─────┬────┘
                                                  │ QMP
                                            ┌─────▼────┐
                                            │  Win98   │
                                            │  Guest   │
                                            │ (Pod 1)  │
                                            └──────────┘

Message flow:
1. Win98 guest writes game state → shared memory / named pipe
2. Sidecar state-relay reads state via QMP or shared file
3. Sidecar publishes RNS Resource / Packet to destination hash
4. Remote sidecar receives, writes state via QMP / shared file
5. Remote Win98 guest reads updated state
```

### 3. Backend Monitoring Integration

```
┌──────────┐     HTTP /metrics      ┌──────────────┐
│ Backend  │◄──────────────────────►│ Ret. Sidecar │
│ server.js│                        │ (Pod N)      │
└─────┬────┘                        └──────────────┘
      │                                    │
      │  Prometheus scrape                 │ RNS path
      ▼                                    ▼
┌──────────┐                        ┌──────────────┐
│Prometheus│                        │ Peer Sidecar │
│ /metrics │                        │ (Pod M)      │
└──────────┘                        └──────────────┘

Exposed metrics:
  rns_peers_total           - Number of discovered peers
  rns_messages_sent_total   - Messages sent
  rns_messages_recv_total   - Messages received
  rns_link_rtt_seconds      - Round-trip time per link
  rns_path_quality          - Path quality score (0-1)
```

### 4. End-to-End Message Path

```
     ┌────────────────────────────────────────────────────┐
     │           Reticulum Protocol Stack                  │
     │                                                    │
     │  ┌──────────┐   ┌──────────┐   ┌──────────────┐   │
     │  │App Layer │   │Transport │   │  Interface    │   │
     │  │          │   │ (Link)   │   │(AutoInterface)│   │
     │  │ Resource │──►│ Encrypt  │──►│  UDP mcast   │───┤──► wire
     │  │ / Packet │   │ + FERNET │   │  port 29716  │   │
     │  └──────────┘   └──────────┘   └──────────────┘   │
     │                                                    │
     │  Identity: Ed25519 + X25519 key exchange           │
     │  Encryption: Fernet (AES-128-CBC + HMAC-SHA256)    │
     └────────────────────────────────────────────────────┘
```

## Implementation Plan

### Phase 1 – Sidecar Container (Week 1-2)

| Task | Description |
|------|-------------|
| 1.1 | Create `containers/reticulum-sidecar/Dockerfile` based on `python:3.11-slim` |
| 1.2 | Install `rns` package (`pip install rns`) |
| 1.3 | Generate default Reticulum config with `AutoInterface` |
| 1.4 | Add sidecar to `compose/docker-compose.yml` for each emulator |
| 1.5 | Verify mesh formation with `rnstatus` across all 9 pods |

### Phase 2 – State Relay Service (Week 3-4)

| Task | Description |
|------|-------------|
| 2.1 | Write `state-relay.py` that monitors game state via QEMU QMP |
| 2.2 | Define Reticulum `Destination` for each pod (hash-based addressing) |
| 2.3 | Broadcast state updates as RNS `Packet` objects |
| 2.4 | Receive remote state and inject via QMP |
| 2.5 | Add Prometheus metrics endpoint to sidecar |

### Phase 3 – Helm & K8s Integration (Week 5)

| Task | Description |
|------|-------------|
| 3.1 | Add sidecar container spec to `helm/loco-chart/templates/statefulset.yaml` |
| 3.2 | Add ConfigMap for Reticulum configuration |
| 3.3 | Add NetworkPolicy allowing UDP 29716 between emulator pods |
| 3.4 | Add ServiceMonitor for Prometheus scraping |

### Phase 4 – Benchmarking & Validation (Week 6)

| Task | Description |
|------|-------------|
| 4.1 | Run E2E benchmark harness (`benchmark/reticulum_bench.py`) |
| 4.2 | Measure RTT, throughput, and message loss across 1/3/9 pod topologies |
| 4.3 | Compare with direct TCP/UDP baseline |
| 4.4 | Document results in performance report |

## Sidecar Container Design

```dockerfile
# containers/reticulum-sidecar/Dockerfile
FROM python:3.11-slim
RUN pip install --no-cache-dir rns
COPY config /etc/reticulum/config
COPY state-relay.py /app/state-relay.py
EXPOSE 4242 29716/udp 9100
ENTRYPOINT ["rnsd", "--config", "/etc/reticulum"]
```

### Docker Compose Addition

```yaml
# Added to each emulator service in compose/docker-compose.yml
reticulum-0:
  build: ./containers/reticulum-sidecar
  network_mode: "service:emulator-0"  # shares network namespace
  volumes:
    - ./config/reticulum:/etc/reticulum
  depends_on:
    - emulator-0
```

By using `network_mode: "service:emulator-0"`, the sidecar shares the
emulator's network namespace and can communicate via `localhost` with the
QEMU guest while also being visible on the `loco-network` bridge for
Reticulum auto-discovery.

## Security Considerations

1. **End-to-end encryption**: All Reticulum traffic is encrypted with
   Fernet (AES-128-CBC + HMAC-SHA256) after X25519 key exchange.
2. **Identity verification**: Each pod has a unique Ed25519 identity,
   preventing impersonation.
3. **Network isolation**: The `loco-network` bridge is internal; the
   `AutoInterface` `discovery_scope = link` prevents leaking to external
   networks.
4. **No secrets in config**: Identity keys are generated at first boot and
   stored in the sidecar's ephemeral filesystem (or a Kubernetes Secret
   for persistence).

## Resource Estimates

| Resource | Per-pod (sidecar) | 9-pod cluster |
|----------|-------------------|---------------|
| RAM      | ~8 MB             | ~72 MB        |
| CPU      | <1 % idle, ~3 % active | <10 % total |
| Disk     | ~25 MB (image)    | 25 MB (shared layers) |
| Network  | ~1 KB/s idle (announces) | ~10 KB/s |
| Ports    | 4242/tcp, 29716/udp | 18 ports total |

## References

- [Reticulum Network Manual](https://reticulum.network/manual/)
- [AutoInterface Configuration](https://reticulum.network/manual/interfaces.html#interfaces-auto)
- [Reticulum Python API](https://markqvist.github.io/Reticulum/manual/reference.html)
- [RNS GitHub Repository](https://github.com/markqvist/Reticulum)
