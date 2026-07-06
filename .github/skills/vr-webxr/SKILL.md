---
name: vr-webxr
description: 'VR and WebXR specialist for Lego Loco Cluster. Covers A-Frame scenes, spatial audio HRTF, WebXR device APIs, 3D sound positioning, media recording/export (WebM, MP4, GIF), and VR performance with 9 streams.'
---

# VR/WebXR Skill

## When to Use
- Building A-Frame VR scenes or components
- Tuning spatial audio (HRTF, distance models, panning)
- WebXR device integration
- Media recording/export in VR
- Performance profiling with 9 simultaneous streams

## Key Files
- `frontend/src/VRScene.jsx` — main VR scene
- `frontend/src/components/VR*.jsx` — VR sub-components
- `frontend/src/hooks/useSpatialAudio.js` — spatial audio hook
- `frontend/src/hooks/useWebRTC.js` — WebRTC stream hook

## Procedure
1. Read current VR components and hooks
2. Check `docs/knowledge/vr-webxr/` for prior findings
3. Implement using A-Frame entity-component patterns
4. Test desktop mode first, then VR headset
5. Verify 60fps with 9 active streams
6. Document in `docs/knowledge/vr-webxr/<date>-<topic>.md`

## Tasks: V1 (spatial audio edges), V2 (performance), V3 (multi-format export)
