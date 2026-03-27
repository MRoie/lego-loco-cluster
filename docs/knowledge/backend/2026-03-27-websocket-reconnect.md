# WebSocket Reconnect Resilience

**Date**: 2026-03-27  
**Author**: @backend-lead  
**Task**: B2 — WebSocket reconnect resilience  
**Tags**: websocket, reconnect, backoff, heartbeat, resilience

---

## Summary

Added a resilient `useWebSocket` hook and upgraded all frontend WebSocket connections to auto-reconnect with exponential backoff. Server-side heartbeat support was added to detect and terminate stale connections.

## What Changed

### New: `frontend/src/hooks/useWebSocket.js`

Generic hook that wraps the browser `WebSocket` API with:

| Feature | Detail |
|---------|--------|
| **Exponential backoff** | 1 s → 2 s → 4 s → 8 s … capped at 30 s |
| **Jitter** | 0-30 % random jitter on each delay to avoid thundering herd |
| **Max attempts** | Default 50 before entering `FAILED` state |
| **Connection states** | `connecting`, `connected`, `disconnected`, `reconnecting`, `failed` |
| **Heartbeat** | Application-level `__ping`/`__pong` every 30 s; stale connections closed after 10 s timeout |
| **Message queue** | Messages sent while disconnected are queued and replayed on reconnect |
| **Custom events** | `window` fires `ws:statechange` events; `onStateChange` callback also available |
| **Cleanup** | Timers, socket, and heartbeat all cleaned up on component unmount |

### Modified: `frontend/src/ActiveContext.jsx`

- Replaced inline `new WebSocket(…)` with `useWebSocket('/active', { … })`
- Exposes `wsState` through context so any component can show connection status
- Re-fetches active state on reconnect so UI is immediately in sync
- Queues active-set messages during disconnection

### Modified: `frontend/src/hooks/useWebRTC.js`

- Upgraded the signaling WS reconnect from a flat 1 s delay to exponential backoff (1 s–30 s with jitter)
- Added max reconnect attempts (50)
- Resets backoff counter on successful connection

### Modified: `backend/server.js`

- Added `setupWsHeartbeat()` helper running 30 s native WS ping intervals on `activeWss` and `signalWss`
- Connections that don't respond with pong are terminated
- Added `handleAppPing()` to echo `__ping` → `__pong` for application-level heartbeat
- New connections initialised with `isAlive = true` via `initWsAlive()`

## Backoff Formula

```
delay = min(baseDelay × 2^attempt + random(0, 0.3 × baseDelay × 2^attempt), maxDelay)
```

With defaults: base = 1 000 ms, max = 30 000 ms, max attempts = 50.

## State Machine

```
DISCONNECTED → CONNECTING → CONNECTED
                                ↓ (close/error)
                           RECONNECTING ←──── backoff timer
                                ↓ (max attempts)
                             FAILED
```

Manual `reconnect()` resets attempt counter and transitions back from FAILED.

## Design Decisions

1. **Application-level ping over native WS ping** — Many HTTP proxies (nginx, envoy) don't forward native WS ping frames. Application-level `__ping`/`__pong` JSON messages pass through all proxy layers. We still use native pings on the server side as a fallback.

2. **Queue over drop** — Messages sent during disconnection are queued (bounded by reconnect window). This avoids losing active-focus changes when the network blips.

3. **Separate hook from useWebRTC** — The signaling WS in `useWebRTC` is tightly coupled to the RTCPeerConnection lifecycle (register → offer → answer → ICE). A generic hook can't manage that handshake, so we enhanced `useWebRTC` inline with the same backoff strategy instead.

4. **30 s heartbeat** — Matches common load-balancer idle timeout defaults (60 s for nginx, 60 s for AWS ALB). Sending at half the timeout prevents most premature closes.

## Edge Cases & Gotchas

- **Thundering herd**: Without jitter, all browser tabs reconnect at the exact same intervals after a backend restart. The 0–30 % jitter spreads reconnects over time.
- **Tab visibility**: Browsers throttle timers in background tabs. Heartbeat timeouts may fire late, but this is benign — the next native pong from the server will restore the alive flag.
- **Stale closure**: The hook guards against acting on a closed component (`unmountedRef`) so late async callbacks don't trigger React state updates on unmounted components.

## Testing

- Verify auto-reconnect: stop backend, start backend → frontend reconnects without page refresh
- Verify backoff: observe console logs showing increasing delay per attempt
- Verify heartbeat: inspect WS frames in DevTools → `__ping`/`__pong` every 30 s
- Verify queue replay: disconnect network, trigger active change, reconnect → change applied
- Verify cleanup: navigate away from page → no leaked timers or sockets
