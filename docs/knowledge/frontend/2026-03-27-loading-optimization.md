# Loading Optimization

**Date**: 2026-03-27  
**Domain**: Frontend  
**Author**: Frontend Lead  
**Tags**: vite, lazy-loading, code-splitting, performance

## Summary

Added lazy loading and code splitting to the frontend to improve initial load time. Heavy components (`VRScene`, `QualityDashboard`) are loaded on demand via `React.lazy` + `Suspense`, and Vite's Rollup config splits vendor bundles.

## Changes

### App.jsx — Lazy Loading

- `VRScene` is now loaded via `React.lazy(() => import('./VRScene'))` and wrapped in `<Suspense>`. It only loads when the user enters VR mode.
- `QualityDashboard` is lazy-loaded similarly — only fetched when rendered.
- Fallback shows a simple loading spinner with Lego blue color.

### vite.config.js — Manual Chunks

Added `rollupOptions.output.manualChunks` to group dependencies:

| Chunk | Contents | Rationale |
|-------|----------|-----------|
| `vendor` | `react`, `react-dom` | Core framework, rarely changes |
| `vr` | `aframe`, `three` | Large 3D libs, only needed in VR mode |
| `dashboard` | `chart.js`, `recharts` (future) | Dashboard visualization libs |
| `animation` | `framer-motion` | Animation, used broadly but separable |

## Expected Impact

- Initial JS bundle reduced by ~40% (aframe alone is ~1.2 MB minified)
- VR scene code only downloaded when user clicks the VR button
- Dashboard code deferred until quality tab is opened
- Vendor chunk cached long-term (content-hash filenames)

## Edge Cases

- `Suspense` fallback prevents blank screen during chunk download
- Pre-existing `import 'aframe'` in VRScene.jsx means the side-effect registration happens at load time — correct since it's only imported when VR mode activates
- `framer-motion` is used in App.jsx directly, so it loads upfront; moved to its own chunk so the main vendor chunk stays small

## Cross-Team References

- **Stream Quality Lead**: `QualityDashboard` lazy-loaded as part of this optimization
- **Design Lead**: Loading spinner uses Lego blue (#0055BF)
