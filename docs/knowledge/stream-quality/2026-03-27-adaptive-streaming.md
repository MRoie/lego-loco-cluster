# Adaptive Streaming Implementation

**Date**: 2026-03-27  
**Domain**: Stream Quality  
**Author**: Stream Quality Lead  
**Tags**: webrtc, adaptive-bitrate, packet-loss, quality

## Summary

Implemented quality-adaptive streaming in `frontend/src/hooks/useAdaptiveStreaming.js` that monitors WebRTC packet loss statistics from the `useWebRTC` hook and dynamically adjusts video encoding parameters via `RTCRtpSender.setParameters()`.

## Thresholds

| Metric | Threshold | Action |
|--------|-----------|--------|
| Packet loss > 5% | Moderate | Reduce framerate to 15 fps |
| Packet loss > 10% | Severe | Reduce framerate to 15 fps AND resolution by 2× (effectively 640×480 from 1280×960) |
| Packet loss < 2% for 30s | Recovery | Restore original quality (30 fps, full resolution) |

## Quality Presets

- **Full**: 30 fps, `scaleResolutionDownBy: 1.0`
- **Reduced FPS**: 15 fps, `scaleResolutionDownBy: 1.0`
- **Reduced All**: 15 fps, `scaleResolutionDownBy: 2.0`

## Design Decisions

1. **Hysteresis via hold period**: Quality is only restored after 30 continuous seconds below the 2% threshold. This prevents oscillation between quality levels during intermittent loss.

2. **RTCRtpSender.setParameters()**: Used instead of renegotiation for seamless quality changes without ICE restart. Works on all modern browsers.

3. **Hook-based architecture**: `useAdaptiveStreaming(peerConnection, stats)` takes the PC and stats from `useWebRTC`, making it composable and testable.

4. **No automatic codec switching**: Codec fallback (VP8 → VP9) is handled separately; this hook focuses on encoding parameter adjustments only.

## Integration

```jsx
import useWebRTC from './hooks/useWebRTC';
import useAdaptiveStreaming from './hooks/useAdaptiveStreaming';

function StreamTile({ instanceId }) {
  const { videoRef, stats } = useWebRTC(instanceId);
  const { currentQuality, isAdapting } = useAdaptiveStreaming(pc, stats);
  // ...
}
```

## Edge Cases

- If `RTCRtpSender.setParameters()` fails (e.g. no active sender), the error is logged but no crash occurs.
- Stats polling interval from `useWebRTC` is 2 seconds — adaptive decisions inherit this cadence.
- On connection reset, quality resets to full automatically since `stats` resets.

## Cross-Team References

- **Frontend Lead**: `useAdaptiveStreaming` exposes `{ currentQuality, isAdapting, thresholds }` for dashboard display (F2).
- **QA Lead**: Test suite at `tests/stream-quality.spec.js` covers degraded network scenarios (S3).
