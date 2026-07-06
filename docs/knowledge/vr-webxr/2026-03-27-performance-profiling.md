# VR Scene Performance Profiling — Knowledge Entry

**Date**: 2026-03-27
**Task**: V2 — VR Scene Performance Profiling
**Agent**: @vr-lead

## Summary

Created `tests/vr-performance.spec.js` — a Playwright test suite that profiles VR scene performance with increasing stream counts (1, 3, 6, 9).

## Test Coverage

| Area | Tests | Metrics Tracked |
|------|-------|----------------|
| FPS with stream counts | 4 | avgFps, minFps, p95/p99 frame time |
| Paint timing | 2 | FCP, rAF jitter |
| Memory usage | 2 | Heap growth, detached DOM nodes |
| Performance API | 2 | Long tasks, resource loading |

**Total**: 10 tests

## Performance Thresholds

| Metric | Target | Rationale |
|--------|--------|-----------|
| Average FPS | ≥30 (CI), ≥60 (interactive) | CI environments have limited GPU; real target is 60fps |
| P95 frame time | <50ms | Equivalent to 20fps floor |
| FCP | <3s | Standard web performance target |
| Memory growth (30s) | <100MB | Prevents unbounded leak |
| DOM node growth | <50% | After navigation round-trip |
| Long task duration | <200ms | Avoids blocking main thread |
| Page load | <10s | CI tolerance with mocked APIs |

## Implementation Notes

- **Frame tracking**: Uses `requestAnimationFrame` loop injected via `addInitScript`, stores delta times
- **Memory**: Uses Chrome-only `performance.memory` API (skips on Firefox/WebKit)
- **API mocking**: `page.route()` intercepts `/api/config/instances` and `/api/status` to control stream count
- **Annotations**: All metrics emitted as `testInfo.annotations` for Playwright HTML report
- **Long tasks**: PerformanceObserver with `longtask` entry type (Chrome 58+)

## Bottleneck Analysis

1. **A-Frame texture updates**: Each tile calls `requestAnimationFrame(updateTexture)` with `material.map.needsUpdate = true` — this is N rAF loops for N tiles
2. **Audio level propagation**: `setAudioLevels` triggers React re-render on every audio tick
3. **VNC canvas rendering**: Each VRReactVNCViewer independently renders to a canvas element

## Recommendations

- Consider batching texture updates into a single rAF loop
- Throttle audio level state updates (e.g., every 100ms instead of every frame)
- Profile with Chrome DevTools Performance tab for real GPU metrics
