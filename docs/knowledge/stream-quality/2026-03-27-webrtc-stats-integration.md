# WebRTC Stats Integration — Task S1

**Date**: 2026-03-27  
**Author**: @stream-lead  
**Status**: Implemented  
**Tags**: webrtc, rtcstats, monitoring, useWebRTC

## Summary

Extended the `useWebRTC` hook (`frontend/src/hooks/useWebRTC.js`) with detailed RTCPeerConnection statistics polling, exposing bandwidth, codec, latency, packet loss, framerate, resolution, and jitter to downstream consumers.

## Changes

### Bug Fix
- **`prevStatsRef` was never declared** — the existing code referenced `prevStatsRef.current` for delta-based bitrate/framerate calculations but never called `useRef({})`. This caused a runtime crash the first time stats were polled. Added `const prevStatsRef = useRef({})` and cleared it on unmount.

### New Stats Fields
| Field | Source | Unit | Notes |
|-------|--------|------|-------|
| `bandwidth.inbound` | `inbound-rtp` bytesReceived delta | bytes/sec | Video receive bandwidth |
| `bandwidth.outbound` | `outbound-rtp` bytesSent delta | bytes/sec | Video send bandwidth (recvonly = 0 typically) |
| `codec` | `codec` report via `inbound-rtp.codecId` | string | e.g. `video/VP8`, `video/H264` |
| `audioCodec` | `codec` report via audio `inbound-rtp.codecId` | string | e.g. `audio/opus` |
| `jitter` | `inbound-rtp.jitter` | ms | Converted from seconds |
| `packetLoss` | `inbound-rtp` packetsLost / total | % (2 decimal) | Rounded to hundredths |
| `latency` | `candidate-pair.currentRoundTripTime` | ms | Only from succeeded pairs |
| `framerate` | `inbound-rtp` framesDecoded delta | fps | Integer |
| `resolution` | `inbound-rtp` frameWidth × frameHeight | string | e.g. `1024x768` |

### Polling
- Changed from 1s → **2s** interval to reduce CPU overhead on the stats loop.
- Added guard: `if (pc.connectionState === 'closed') return` to skip polling on dead connections.

### API
- Return shape now includes `stats` alias alongside existing `connectionQuality` for backward compatibility.
- `const { stats } = useWebRTC(instanceId)` — new preferred API.
- `const { connectionQuality } = useWebRTC(instanceId)` — still works (same object).

## Edge Cases Handled
- **Stats not available yet**: Metrics default to zeroes/null until the first successful `getStats()` call.
- **Connection closed**: Guard skips polling; cleanup clears interval.
- **Missing codec reports**: `codec`/`audioCodec` remain `null` when `codec`-type stats aren't present.
- **Zero packets**: Packet loss returns 0 when total packets is 0 (no division by zero).

## Consumers
- `frontend/src/components/InstanceCard.jsx` — uses `connectionQuality` (unchanged contract).
- `frontend/src/VRScene.jsx` — uses `videoRef` and `audioLevel` only (unaffected).

## What's Next
- **S2**: Quality-adaptive streaming — use `packetLoss` and `jitter` to auto-reduce resolution/framerate.
- **S3**: Stream quality test suite — mock `getStats()` responses to verify metric extraction.
- **F2**: Frontend quality dashboard — bind `stats` object to live UI charts.

## Key Learnings
1. The W3C `RTCStatsReport` uses `report.kind` (not `report.mediaType`) in modern browsers. Updated selector from `mediaType === 'video'` to `kind === 'video'`.
2. Codec info lives in separate `codec`-type reports referenced by `codecId` from `inbound-rtp`. Must do a two-pass scan (collect codecs first, then resolve references).
3. `jitter` from `inbound-rtp` is in seconds (float), not ms — needs × 1000 conversion.
4. `prevStatsRef` must be cleared on unmount to prevent stale deltas when the component remounts for the same instance.
