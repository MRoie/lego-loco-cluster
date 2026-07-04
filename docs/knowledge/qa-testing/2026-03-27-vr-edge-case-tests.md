# VR Edge Case Test Suite — Knowledge Entry

**Date**: 2026-03-27
**Task**: Q2 — VR Edge Case Test Suite
**Agent**: @qa-lead

## Summary

Created `tests/vr-edge-cases.spec.js` — a comprehensive Playwright test suite covering audio modes, export formats, browser differences, XR session lifecycle, and texture cleanup.

## Test Coverage

| Area | Tests | Notes |
|------|-------|-------|
| Audio Modes | 4 | stereo, HRTF, equalpower, mode switching |
| Export Formats | 7 | WebM, MP4, GIF, MKV, MP3, disable during recording, MIME selection |
| Chromium-specific | 2 | VP9 codec, performance.memory |
| Firefox-specific | 2 | Standard AudioContext, VP8 fallback |
| WebKit-specific | 2 | webkitAudioContext, MediaRecorder availability |
| XR Session Lifecycle | 5 | isSessionSupported, requestSession, end, referenceSpace, multi-session |
| Video Texture Cleanup | 4 | A-Frame assets removal, canvas null, rAF stop, AudioContext close |

**Total**: 26 tests

## Browser Compatibility Matrix

| Feature | Chromium | Firefox | WebKit |
|---------|----------|---------|--------|
| AudioContext | ✅ | ✅ | ✅ (webkit prefix fallback) |
| MediaRecorder WebM | ✅ VP9 | ✅ VP8 | ❓ Limited |
| MediaRecorder MP4 | ✅ Chrome 114+ | ❌ | ❌ |
| performance.memory | ✅ | ❌ | ❌ |
| WebXR API | ✅ | ❓ Behind flag | ❌ |
| PerformanceObserver longtask | ✅ | ❌ | ❌ |

## Export Format Support

From `frontend/src/utils/mediaExport.js`:

| Format | MIME | Fallback Strategy |
|--------|------|-------------------|
| WebM | video/webm;codecs=vp9 | video/webm |
| MP4 | video/mp4;codecs=avc1 | Record as WebM, rename |
| MKV | video/x-matroska | WebM container (subset of MKV) |
| GIF | image/gif | Canvas frame capture pipeline |
| MP3 | audio/mpeg | audio/webm;codecs=opus renamed |

## XR Session Lifecycle

Tested flow: `isSessionSupported` → `requestSession` → `requestReferenceSpace` → interact → `end()`

Key finding: A-Frame manages its own XR session entry/exit, but custom code may need to coordinate with A-Frame's `enterVR`/`exitVR` events.

## Cleanup Verification

1. **A-Frame assets**: Removed from DOM on navigation (React unmount)
2. **Canvas textures**: `material.src = null` on VNC disconnect
3. **rAF loops**: Stop when component unmounts (cleanup in useEffect return)
4. **AudioContext**: `close()` called in VRScene useEffect cleanup
