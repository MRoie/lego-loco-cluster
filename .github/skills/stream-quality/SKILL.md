---
name: stream-quality
description: 'Stream quality monitoring for Lego Loco Cluster. Covers WebRTC statistics, VNC fallback, codec selection (VP8/H.264), GStreamer pipelines, quality-adaptive streaming, and latency optimization.'
---

# Stream Quality Skill

## When to Use
- WebRTC stream quality debugging
- VNC fallback configuration
- Codec selection and tuning
- GStreamer pipeline changes
- Quality monitoring and adaptive streaming

## Key Files
- `backend/services/streamQualityMonitor.js` — quality monitor
- `backend/services/udpToWebrtc.js` — UDP-to-WebRTC bridge
- `frontend/src/hooks/useWebRTC.js` — WebRTC hook
- `config/webrtc.json` — WebRTC config

## Procedure
1. Review streaming pipeline end-to-end
2. Check `docs/knowledge/stream-quality/` for prior findings
3. Implement with codec/bandwidth testing
4. Document in `docs/knowledge/stream-quality/<date>-<topic>.md`

## Tasks: S1 (RTCStats), S2 (adaptive streaming), S3 (quality tests)
