# Accessibility Audit — WCAG 2.1 AA Compliance

**Date**: 2026-03-27
**Author**: @design-lead
**Task**: D2
**Status**: finding

## Scope

Audit of the Lego Loco Cluster dashboard (React + Tailwind) and VR scene against WCAG 2.1 Level AA. Components reviewed:

- [App.jsx](../../../frontend/src/App.jsx) — main layout, grid, keyboard handling
- [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx) — card component with audio controls
- [DiscoveryStatus.jsx](../../../frontend/src/components/DiscoveryStatus.jsx) — status indicator dots
- [QualityDashboard.jsx](../../../frontend/src/components/QualityDashboard.jsx) — metrics display
- [VRScene.jsx](../../../frontend/src/VRScene.jsx) — A-Frame WebXR scene
- [QualityIndicator.jsx](../../../frontend/src/components/QualityIndicator.jsx) — per-instance quality badge

---

## 1. Color Contrast

### Findings

| Issue | Component | Location | Current Ratio | Required | Status |
|-------|-----------|----------|---------------|----------|--------|
| Yellow warning text on light background | DiscoveryStatus | [DiscoveryStatus.jsx](../../../frontend/src/components/DiscoveryStatus.jsx#L8) `text-yellow-300` | ~2.5:1 | 4.5:1 (AA) | **FAIL** |
| Gray disabled text `#9E9E9E` on white | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L99) placeholder text | 2.8:1 | 4.5:1 (AA) | **FAIL** |
| Green live dot without text alternative | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L252) `bg-green-400` | N/A — color-only info | 3:1 for UI | **FAIL** |
| Status badge color-only differentiation | DiscoveryStatus | [DiscoveryStatus.jsx](../../../frontend/src/components/DiscoveryStatus.jsx#L22-L28) colored dots | N/A | Non-color indicator | **FAIL** |
| Body text on white | App, InstanceCard | General | 17.4:1 | 4.5:1 | PASS |
| Blue link/selected text on white | App | `#0055BF` on white | 7.3:1 | 4.5:1 | PASS |
| Error text `text-red-800` on `bg-red-100` | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L85) | 5.8:1 | 4.5:1 | PASS |

### Action Items — Color Contrast

1. **Replace `text-yellow-300`** in DiscoveryStatus with `text-yellow-700` or the design system's `--color-warning-text-dark` (`#B8860B`) which achieves 4.5:1 on light backgrounds
2. **Disabled text**: Use `#757575` instead of `#9E9E9E` for disabled/muted labels (achieves 4.6:1)
3. **Status dots**: Add text labels or `aria-label` to colored dots — color alone must not be the sole indicator (WCAG 1.4.1)
4. **Live indicator**: Add `aria-label="Live stream active"` to the green pulse dot

---

## 2. Keyboard Navigation

### Findings

| Issue | Component | Location | Status |
|-------|-----------|----------|--------|
| Cards lack `tabIndex` attribute | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L135) `<motion.div onClick>` | **FAIL** |
| No Enter/Space handler on cards | InstanceCard | `onClick` only — no `onKeyDown` equivalent | **FAIL** |
| Hotkey handler uses physical key combos | App | [App.jsx](../../../frontend/src/App.jsx#L88-L108) global `keydown` | **WARN** — may conflict with assistive tech |
| Volume slider is keyboard-accessible | InstanceCard | `<input type="range">` | PASS |
| Mute/Record buttons are focusable | InstanceCard | `<button>` elements | PASS |
| VR mode button is keyboard-reachable | App | [App.jsx](../../../frontend/src/App.jsx#L182) `<button onClick>` | PASS |
| No skip-to-content link | App | [App.jsx](../../../frontend/src/App.jsx) — top of page | **FAIL** |
| No visible focus indicator on cards | InstanceCard | Uses `whileHover` only, no `:focus-visible` | **FAIL** |

### Action Items — Keyboard Navigation

1. **Add `tabIndex={0}` and `onKeyDown`** to `InstanceCard` root `<motion.div>`:
   ```jsx
   onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onClick(); } }}
   tabIndex={0}
   role="button"
   ```
2. **Add `:focus-visible` ring** to card styles: `focus-visible:ring-4 focus-visible:ring-blue-400 focus-visible:outline-none`
3. **Add skip-to-content link** at the top of `App.jsx`:
   ```jsx
   <a href="#instance-grid" className="sr-only focus:not-sr-only ...">Skip to instances</a>
   ```
4. **Protect hotkey combos**: Check `e.target.tagName` in the global handler to avoid overriding screen reader shortcuts when focus is on an input element

---

## 3. Screen Reader Labels (ARIA)

### Findings

| Issue | Component | Location | Status |
|-------|-----------|----------|--------|
| Grid container has no `role` or `aria-label` | App | [App.jsx](../../../frontend/src/App.jsx#L199) grid div | **FAIL** |
| Cards have no `aria-label` describing state | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L135) | **FAIL** |
| Status dot has `title` but no `aria-label` | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L157) | **WARN** |
| Mute button has `aria-pressed` | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L170) | PASS |
| Volume slider has `aria-label` | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L181) | PASS |
| Record button has `aria-pressed` | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L201) | PASS |
| Audio level meter has no ARIA | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L215) — visual-only bar | **FAIL** |
| VR scene lacks `aria-label` | VRScene | [VRScene.jsx](../../../frontend/src/VRScene.jsx) `<a-scene>` | **FAIL** |
| SVG VR button icon has no alt text | App | [App.jsx](../../../frontend/src/App.jsx#L190) inline SVG | **FAIL** |

### Action Items — Screen Reader Labels

1. **Instance grid**: Add `role="region"` and `aria-label="Emulator instances"` to the grid container
2. **InstanceCard**: Add `aria-label={`Instance ${instance.name || instance.id}, status: ${getStatusText(instance.status, instance.provisioned)}`}`
3. **Status dot**: Replace `title` with `aria-label` and add `role="status"`
4. **Audio level meter**: Add `role="meter"` with `aria-valuenow`, `aria-valuemin="0"`, `aria-valuemax="100"`, `aria-label="Audio level"`
5. **VR scene**: Add `aria-label="3D VR scene with instance streams"` to `<a-scene>`
6. **VR button SVG**: Add `aria-hidden="true"` to the SVG and ensure the parent `<button>` has `aria-label="Enter VR mode"`

---

## 4. Motion & Animation Preferences

### Findings

| Issue | Component | Location | Status |
|-------|-----------|----------|--------|
| Framer Motion animations everywhere | App, InstanceCard | `<motion.div>` with `whileHover`, `animate` | **WARN** |
| Pulse shimmer on loading cards | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L291) `animate={{ scale: [1, 1.1, 1] }}` | **FAIL** |
| Live indicator pulsing | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L252) `animate-pulse` | **WARN** |
| Record button pulsing on active | InstanceCard | [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx#L204) `animate-pulse` | **WARN** |
| No `prefers-reduced-motion` media query | Global | No CSS or JS check found | **FAIL** |
| Stagger animation on grid load | App | [App.jsx](../../../frontend/src/App.jsx#L209) `delay: index * 0.1` | **WARN** |

### Action Items — Motion Preferences

1. **Add CSS media query** to the global stylesheet:
   ```css
   @media (prefers-reduced-motion: reduce) {
     *, *::before, *::after {
       animation-duration: 0.01ms !important;
       animation-iteration-count: 1 !important;
       transition-duration: 0.01ms !important;
     }
   }
   ```
2. **Respect in Framer Motion**: Create a hook that reads `prefers-reduced-motion` and passes `animate={false}` or reduced values:
   ```jsx
   const prefersReduced = useReducedMotion(); // from framer-motion
   // Then: <motion.div animate={prefersReduced ? {} : { scale: [1, 1.1, 1] }}>
   ```
3. **Replace `animate-pulse` with static indicators** when reduced motion is preferred

---

## 5. VR Scene Accessibility

### Findings

| Issue | Severity | Status |
|-------|----------|--------|
| No alternative non-VR view for spatial audio controls | High | **FAIL** |
| A-Frame `<a-scene>` traps focus — no way to Tab out | High | **FAIL** |
| No text alternatives for 3D-positioned tiles | Medium | **FAIL** |
| Spatial audio has no 2D fallback mixer | Medium | **WARN** |
| Escape key exits VR mode (good) | — | PASS |

### Action Items — VR Accessibility

1. **Add "Exit VR" button** always visible in VR overlay (not just Escape key), with high contrast and `aria-label`
2. **Provide 2D alternative view**: When VR is active, maintain a hidden accessible DOM rendering of instance names and statuses for screen readers
3. **Focus trap management**: Use `inert` attribute on background content when VR is active, and ensure focus is set to the exit button on VR entry
4. **2D audio mixer fallback**: Offer a flat volume mixer panel (accessible via keyboard) as an alternative to spatial audio positioning

---

## Summary of Action Items

| # | Category | Priority | Effort |
|---|----------|----------|--------|
| 1 | Fix yellow text contrast | High | Low |
| 2 | Fix disabled text contrast | Medium | Low |
| 3 | Add non-color status indicators | High | Medium |
| 4 | Add `tabIndex` + keyboard handlers to cards | High | Low |
| 5 | Add `:focus-visible` ring to cards | High | Low |
| 6 | Add skip-to-content link | Medium | Low |
| 7 | Add ARIA labels to grid, cards, status dots | High | Medium |
| 8 | Add ARIA to audio level meter | Medium | Low |
| 9 | Add `aria-label` to VR scene and button | Medium | Low |
| 10 | Add `prefers-reduced-motion` CSS | High | Low |
| 11 | Integrate Framer Motion `useReducedMotion` | Medium | Medium |
| 12 | VR focus trap + exit button | High | Medium |
| 13 | 2D fallback for VR scene | High | High |

## References

- [Design System](design-system.md) — color palette, contrast ratios, accessibility section
- WCAG 2.1 Quick Reference: https://www.w3.org/WAI/WCAG21/quickref/
- Framer Motion `useReducedMotion`: https://www.framer.com/motion/use-reduced-motion/
