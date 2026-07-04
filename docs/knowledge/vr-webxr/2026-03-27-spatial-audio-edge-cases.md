# VR Spatial Audio Edge Case Testing — Knowledge Entry

**Date**: 2026-03-27
**Task**: V1 — VR Spatial Audio Edge Case Testing
**Agent**: @vr-lead

## Summary

Created `tests/vr-spatial-audio.spec.js` — a Playwright test suite covering spatial audio edge cases in the VR scene.

## Test Coverage

| Area | Tests | Notes |
|------|-------|-------|
| HRTF Distance Models | 4 | inverse, linear, exponential + default check |
| Mono/3D Toggle | 4 | HRTF vs equalpower, button toggle, channel merger routing |
| Autoplay Resume | 4 | Suspended state, Enable Audio click, resume() call, button disappearance |
| AudioContext State | 4 | suspended→running, close(), shared context reuse, cleanup on unmount |
| Spatial Positioning | 4 | Panner creation, grid layout formula, Z=-3 position, linearRamp |
| Mute/Unmute | 5 | Button presence, mute→gain=0, unmute restore, mute indicator, slider |

**Total**: 25 tests

## Key Findings

- **useSpatialAudio hook** uses `HRTF` panning model for 3D and `equalpower` for mono (accessibility fallback)
- **Distance model** defaults to `inverse` with rolloffFactor=1, matching Web Audio spec
- **Shared AudioContext** pattern: VRScene creates one context passed to all VRTile components
- **Autoplay policy**: The "Enable Audio" button calls `ctx.resume()` on user gesture
- **Mute implementation**: Sets gain to 0 via `linearRampToValueAtTime`, does not disconnect nodes
- **Channel merger**: Mono mode routes through `createChannelMerger(1)` before panner

## Implementation Notes

- Tests use injected mock AudioContext and XR APIs (navigator.xr)
- Mocks track all calls in `window.__audioMock` for assertion
- Tests are resilient to pages that don't render VR (graceful skips via count checks)
- Grid position formula: `x = (i % cols - (cols-1)/2) * 1.4`, `y = ((rows-1)/2 - row) * 1.0`, `z = -3`

## Edge Cases Identified

1. AudioContext can be garbage collected if not stored in ref — VRScene uses state + useCallback
2. `webkitAudioContext` fallback needed for older Safari
3. Muting then unmuting should restore the *computed* volume (master × ambient ratio), not always 1.0
4. Shared context cleanup on unmount must call `close()` to release audio hardware
