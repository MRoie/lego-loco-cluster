# VR Desktop Streaming Master Plan

This document outlines the planned work to deliver a full VR desktop experience with nine simultaneous Windows 98 instances. It expands on `docs/FUTURE_TASKS.md` and tracks the integration of WebRTC streaming with WebXR.

## Architecture Diagram
```mermaid
graph LR
  subgraph VR Client
    HMD[Quest 3/Quest 1 Browser]
    WebXR[A-Frame/Three.js WebXR Shell]
  end
  HMD --> WebXR
  subgraph Network
    TURN[STUN/TURN (STUNner)]
  end
  WebXR -- WebRTC video+input --> TURN
  subgraph K8s Cluster
    style K8s Cluster fill:#eef,stroke:#889,stroke-width:1px
    VM1[Win98 VM 1]
    VM2[...]
    VM9[Win98 VM 9]
    InputProxy[Input Proxy Svc]
    PV[Shared PVC / CephFS]
  end
  TURN -->|P2P or relayed| VM1 & VM2 & VM9
  InputProxy --> VM1 & VM2 & VM9
  PV --- VM1 & VM2 & VM9
```

## Objectives
- **Multi-desktop VR:** Show nine Windows 98 desktops in one VR scene.
- **Codec matrix:** Benchmark H.264, VP8 and MJPEG encoding at 1024×768.
- **Optional pipelines:** Support Sunshine/Moonlight and Parsec for non-VR use.
- **Zero-install client:** Serve the WebXR page from the cluster ingress.
- **Full CI + E2E tests:** Run headless WebXR checks via Playwright.

## Task Matrix
The following table maps upcoming tasks to repository deliverables.

| ID | Task Title | Key Deliverables |
|----|------------|-----------------|
|T-01|Build base Win98 SoftGPU image|`qcow2` image + packer script|
|T-02|Containerize VM runner|Dockerfile + `start.sh` sidecar|
|T-03|Helm chart (9 replicas)|`charts/loco-vm` with STUNner sub-chart|
|T-04|WebXR front-end|`frontend/webxr/` app|
|T-05|Input proxy service|`cmd/input-proxy` binary|
|T-06|Sunshine host PoC|`Dockerfile.sunshine` + docs|
|T-07|Parsec host PoC|Updated qcow2, docs|
|T-08|Codec benchmark harness|`bench.py` and results.csv|
|T-09|Playwright WebXR E2E|`tests/e2e_vr.spec.ts`|
|T-10|Observability stack|`monitoring/` kustomize configs|

Refer to `docs/FUTURE_TASKS.md` for a condensed list of next actions.

## Benchmark Harness

Run `python3 benchmark/bench.py` to deploy 1, 3 and 9 VR-enabled instances
sequentially. The script collects placeholder FPS and bitrate metrics and writes
them to `results.csv` for future analysis.

