# Handover: VNC Streaming Debugging & Observability

**Date:** 2025-12-06
**Status:** Deployment Stable, VNC Stream Not Visible
**Priority:** High

## 1. Executive Summary
The Minikube deployment of the Lego Loco Cluster is now **stable**. All services (Backend, Frontend, VR, Emulator) start correctly, pass health checks, and are discoverable. The critical "CrashLoopBackOff" and "Init" failures have been resolved.

**Current Blocker:** Despite the stable infrastructure and passing connectivity tests (OSI Layer 3/4), the **VNC video stream is not visible in the Frontend UI**. The connection appears to establish (or at least doesn't immediately fail), but no video data is rendered.

## 2. System State & Recent Fixes

### Infrastructure (Stable)
- **Emulator**:
    - Switched to `hostPath` storage (fixed NFS mount failures).
    - Replaced bash health check with **Python `http.server`** (fixed "Connection Refused" / "Invalid Header").
    - Updated `pgrep` to handle truncated process names (fixed QEMU detection).
- **Backend**:
    - Implemented **DNS-based addressing** (`<pod>.<service>...`) for VNC URLs (fixed `ENOTFOUND`).
    - Enforced resource limits to prevent `OOMKilled`.
- **Deployment**:
    - Standardized on `helm/loco-chart/values-minikube-hostpath.yaml`.
    - Created `scripts/deploy_backend_rigorous.sh` for reliable builds.

### Observability (Implemented)
- **Frontend**:
    - `src/utils/logger.js`: Structured logging to console and backend.
    - `src/utils/metrics.js`: Prometheus-style metrics collection.
    - `src/utils/osiVerification.js`: Diagnostics for Network/Transport layers.
    - `VNCDebugPanel.jsx`: UI overlay for connection stats.
- **Backend**:
    - `/api/logs/frontend`: Endpoint to ingest frontend logs.
    - `/api/metrics/frontend`: Endpoint to ingest frontend metrics.

## 3. The Problem: "Blind" VNC
The system passes all "connectivity" checks:
1.  **L3 (IP)**: Backend can ping Emulator.
2.  **L4 (TCP)**: Backend can connect to Emulator port 5901.
3.  **Discovery**: Backend correctly identifies the Emulator pod and generates a VNC URL.

However, the user reports **no video**. This suggests an issue at **Layer 5 (Session/WebSocket)** or **Layer 7 (Application/RFB Protocol)**.

## 4. Required Next Steps: Deep Instrumentation
To resolve this, we need **comprehensive tracing** of the VNC data path. The "testing" done so far confirmed *reachability*, not *throughput* or *protocol correctness*.

### A. Frontend Instrumentation (`react-vnc` / `rfb`)
The current frontend logs are too high-level ("Connected", "Disconnected").
*   **Action**: Hook into the underlying `rfb` client object if possible.
*   **Action**: Log **WebSocket Close Codes** (e.g., 1006 Abnormal Closure).
*   **Action**: Measure **Time to First Frame**. If it's infinite, we know the handshake finished but data isn't flowing.

### B. Backend Proxy Tracing (`server.js`)
The backend proxies WebSocket traffic to the Emulator's TCP port. We need to know if data is actually moving.
*   **Action**: Instrument the `http-proxy` middleware.
    *   Log `upgrade` events (WebSocket handshake start).
    *   Log `open` events (TCP connection to Emulator).
    *   **CRITICAL**: Log **data throughput** (bytes read/written). Is the Emulator sending *anything* back?
    *   Log `error` events on the proxy socket (e.g., "ECONNRESET").

### C. Emulator Internal Diagnostics
*   **Action**: Check QEMU logs for VNC client connection attempts.
    *   `kubectl logs -n loco loco-loco-emulator-0` (Currently shows QEMU startup, but need to see if it logs connections).
*   **Action**: (Advanced) Run `tcpdump` in the emulator pod (if available) or node to verify packets on port 5901.

### D. Protocol Mismatch Check
*   **Hypothesis**: The Frontend expects a WebSocket (ws://), but the Emulator exposes a raw TCP socket (5901).
*   **Verification**: The Backend *must* be using a **WebSocket-to-TCP bridge** (like `websockify` logic) inside `server.js`.
    *   *Check*: Does `server.js` use `http-proxy` in TCP mode or WS mode?
    *   *Check*: Does the proxy handle the WebSocket handshake, or does it blindly pipe? If it blindly pipes to a raw TCP port, the handshake will fail because QEMU speaks RFB, not HTTP/WS.
    *   **Crucial**: If `server.js` is just an HTTP proxy, it might not be unwrapping the WebSocket frames before sending to QEMU. QEMU's built-in VNC server usually expects raw TCP, not WebSockets (unless configured otherwise).

## 5. Repository Info
- **Branch**: `fix/deployment-stabilization-and-observability`
- **Key Files**:
    - `backend/server.js` (Proxy logic)
    - `frontend/src/hooks/useVNCConnection.js` (Client logic)
    - `helm/loco-chart/templates/configmap-emulator-scripts.yaml` (Health check)

Good luck. The infrastructure is solid; the data pipe is the suspect.
