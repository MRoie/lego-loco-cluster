# Instance Card State Visual Specification

**Date**: 2026-03-27
**Author**: @design-lead
**Task**: D3
**Status**: finding

## Overview

Complete visual specification for all 7 instance card states in the Lego Loco Cluster dashboard. Each state has distinct border, background, icon, animation, and interaction properties. Based on the Lego design system color palette and the existing `InstanceCard.jsx` component.

---

## State Definitions

### 1. Loading

The instance pod is starting and QEMU is booting. Content is unknown.

| Property | Value | Tailwind |
|----------|-------|----------|
| **Border** | 2px solid `#FFD700` (Lego Yellow) | `border-2 border-lego-yellow` |
| **Background** | White `#FFFFFF` | `bg-white` |
| **Text color** | `#F57F17` (dark yellow) | `text-yellow-800` |
| **Icon** | Skeleton placeholder blocks | — (custom shimmer) |
| **Animation** | Pulse shimmer over skeleton content, 2s ease-in-out infinite | `animate-pulse` |
| **Interaction** | Non-interactive (pointer-events: none on stream area) | `pointer-events-none` on content |
| **Status badge** | `LOADING` text, `#FFF8E1` bg, `#F57F17` text | `bg-yellow-50 text-yellow-800` |
| **Content** | Skeleton lines mimicking name, IP, and stream viewport | — |
| **Spinner** | Indeterminate progress bar below header | `lego-progress` with sliding bar |

```jsx
{/* Loading state card */}
<div className="border-2 border-lego-yellow bg-white rounded-lg overflow-hidden">
  <div className="p-4 bg-gradient-to-b from-yellow-100 to-yellow-50 border-b-4 border-red-700">
    <div className="animate-pulse flex items-center justify-between">
      <div className="h-6 w-24 bg-yellow-200 rounded" />
      <div className="h-5 w-5 bg-yellow-200 rounded" />
    </div>
    {/* Progress bar */}
    <div className="mt-3 h-1.5 bg-yellow-200 rounded-full overflow-hidden">
      <div className="h-full w-1/3 bg-lego-yellow rounded-full animate-[slide_1.5s_ease-in-out_infinite]" />
    </div>
  </div>
  <div className="aspect-[4/3] bg-gray-100 animate-pulse">
    <div className="h-full flex items-center justify-center">
      <div className="w-16 h-16 border-3 border-yellow-300 bg-yellow-100 rounded-lg flex items-center justify-center">
        <span className="text-2xl">⚡</span>
      </div>
    </div>
  </div>
</div>
```

### 2. Connecting

VNC/WebRTC handshake is in progress. Instance name is known.

| Property | Value | Tailwind |
|----------|-------|----------|
| **Border** | 2px solid `#FFD700` (Lego Yellow) | `border-2 border-lego-yellow` |
| **Background** | White `#FFFFFF` | `bg-white` |
| **Text color** | `#1B1B1B` primary, `#F57F17` for status | `text-dark` / `text-yellow-800` |
| **Icon** | Spinning circle (animated rotate) | Custom CSS or SVG spinner |
| **Animation** | Rotate 1s linear infinite on spinner icon | `animate-spin` |
| **Interaction** | Click-selectable but no stream controls | `cursor-pointer` |
| **Status badge** | `CONNECTING` text, `#FFF8E1` bg | `bg-yellow-50 text-yellow-800` |
| **Content** | Instance name visible, connection progress percentage | — |

```jsx
{/* Connecting state card */}
<div className="border-2 border-lego-yellow bg-white rounded-lg overflow-hidden cursor-pointer">
  <div className="p-4 bg-gradient-to-b from-yellow-100 to-yellow-50 border-b-4 border-red-700">
    <div className="flex items-center justify-between">
      <span className="text-sm font-bold text-dark tracking-wide uppercase">MARY</span>
      <div className="flex items-center gap-2">
        <svg className="w-5 h-5 animate-spin text-lego-yellow" viewBox="0 0 24 24">
          <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" fill="none" strokeDasharray="60 20" />
        </svg>
        <span className="text-xs font-medium text-yellow-800 bg-yellow-50 px-2 py-0.5 rounded-full">CONNECTING</span>
      </div>
    </div>
  </div>
  <div className="aspect-[4/3] bg-gray-50 flex items-center justify-center">
    <p className="text-sm text-gray-500">Establishing stream…</p>
  </div>
</div>
```

### 3. Streaming

Active video stream from QEMU. The primary interactive state.

| Property | Value | Tailwind |
|----------|-------|----------|
| **Border** | 2px solid `#00A651` (Lego Green) | `border-2 border-lego-green` |
| **Background** | White `#FFFFFF` | `bg-white` |
| **Text color** | `#1B1B1B` primary | `text-dark` |
| **Icon** | Green live dot (⬤) — pulsing | Absolute positioned dot |
| **Animation** | Pulse 2s ease on live dot | `animate-pulse` |
| **Interaction** | Full: click to select, audio controls, record, quality indicator | `cursor-pointer` |
| **Status badge** | `STREAMING` text, `#E8F5E9` bg, `#1B5E20` text | `bg-green-50 text-green-800` |
| **Content** | Live video frame filling the 4:3 aspect viewport | `<video>` or VNC canvas |

```jsx
{/* Streaming state card */}
<div className="border-2 border-lego-green bg-white rounded-lg overflow-hidden cursor-pointer hover:shadow-lg transition-shadow">
  <div className="p-4 bg-gradient-to-b from-yellow-200 to-yellow-100 border-b-4 border-red-700">
    <div className="flex items-center justify-between">
      <span className="text-sm font-bold text-dark tracking-wide uppercase">MARY</span>
      <div className="flex items-center gap-2">
        <span className="relative flex h-3 w-3">
          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75" />
          <span className="relative inline-flex rounded-full h-3 w-3 bg-lego-green" />
        </span>
        <span className="text-xs font-medium text-green-800 bg-green-50 px-2 py-0.5 rounded-full">STREAMING</span>
      </div>
    </div>
    {/* Audio controls row here */}
  </div>
  <div className="aspect-[4/3] bg-black">
    <video className="w-full h-full object-contain" autoPlay playsInline />
  </div>
</div>
```

### 4. Error

QEMU crashed, VNC unreachable, or health check failed.

| Property | Value | Tailwind |
|----------|-------|----------|
| **Border** | 2px solid `#C4281C` (Lego Red) | `border-2 border-lego-red` |
| **Background** | `#FFEBEE` (light red tint) | `bg-red-50` |
| **Text color** | `#B71C1C` (dark red) | `text-red-900` |
| **Icon** | Error triangle ⚠️ | Text emoji or SVG |
| **Animation** | None (errors should not be distracting) | — |
| **Interaction** | Retry button visible, click to attempt reconnection | `cursor-pointer` on retry |
| **Status badge** | `ERROR` text, `#FFEBEE` bg, `#B71C1C` text | `bg-red-50 text-red-900` |
| **Content** | Error icon, error message, retry button | — |

```jsx
{/* Error state card */}
<div className="border-2 border-lego-red bg-red-50 rounded-lg overflow-hidden">
  <div className="p-4 bg-gradient-to-b from-red-100 to-red-50 border-b-4 border-red-700">
    <div className="flex items-center justify-between">
      <span className="text-sm font-bold text-dark tracking-wide uppercase">PETER</span>
      <span className="text-xs font-medium text-red-900 bg-red-100 px-2 py-0.5 rounded-full">ERROR</span>
    </div>
  </div>
  <div className="aspect-[4/3] bg-red-50 flex flex-col items-center justify-center gap-3">
    <div className="w-16 h-16 border-3 border-red-300 bg-red-100 rounded-lg flex items-center justify-center">
      <span className="text-2xl">⚠️</span>
    </div>
    <p className="text-sm font-bold text-red-900">Connection Failed</p>
    <p className="text-xs text-red-700 px-4 text-center">QEMU process exited unexpectedly</p>
    <button className="mt-2 px-4 py-1.5 bg-lego-red text-white text-xs font-bold rounded-md hover:bg-red-700 transition-colors"
            aria-label="Retry connection to PETER">
      Retry
    </button>
  </div>
</div>
```

### 5. Offline

Pod is not running. No instance detected.

| Property | Value | Tailwind |
|----------|-------|----------|
| **Border** | 1px solid `#9E9E9E` (Medium Gray) | `border border-gray-400` |
| **Background** | `#F5F5F5` (Light Gray) | `bg-gray-100` |
| **Text color** | `#9E9E9E` (muted gray) | `text-gray-400` |
| **Icon** | Dash (—) or empty circle | — |
| **Animation** | None | — |
| **Interaction** | Non-interactive (no click handler, no hover effect) | `cursor-default pointer-events-none` |
| **Status badge** | `OFFLINE` text, gray | `bg-gray-200 text-gray-500` |
| **Content** | Muted "Offline" text, no stream area | — |

```jsx
{/* Offline state card */}
<div className="border border-gray-400 bg-gray-100 rounded-lg overflow-hidden opacity-60 cursor-default">
  <div className="p-4 bg-gray-200 border-b-2 border-gray-400">
    <div className="flex items-center justify-between">
      <span className="text-sm font-bold text-gray-400 tracking-wide uppercase">SLOT 5</span>
      <span className="text-xs font-medium text-gray-500 bg-gray-200 px-2 py-0.5 rounded-full">OFFLINE</span>
    </div>
  </div>
  <div className="aspect-[4/3] bg-gray-100 flex flex-col items-center justify-center">
    <div className="w-16 h-16 border-2 border-gray-300 bg-gray-200 rounded-lg flex items-center justify-center">
      <span className="text-2xl text-gray-400">—</span>
    </div>
    <p className="text-sm text-gray-400 mt-3">Offline</p>
  </div>
</div>
```

### 6. Paused

Stream is paused by the user. QEMU instance is still running.

| Property | Value | Tailwind |
|----------|-------|----------|
| **Border** | 2px solid `#0055BF` (Lego Blue) | `border-2 border-lego-blue` |
| **Background** | White `#FFFFFF` | `bg-white` |
| **Text color** | `#0D47A1` (dark blue) | `text-blue-900` |
| **Icon** | Pause icon ⏸ | Text emoji or SVG |
| **Animation** | None (paused = calm) | — |
| **Interaction** | Resume button visible, click to resume stream | `cursor-pointer` on resume |
| **Status badge** | `PAUSED` text, `#E3F2FD` bg, `#0D47A1` text | `bg-blue-50 text-blue-900` |
| **Content** | Last frozen frame (dimmed), pause overlay, resume button | — |

```jsx
{/* Paused state card */}
<div className="border-2 border-lego-blue bg-white rounded-lg overflow-hidden cursor-pointer">
  <div className="p-4 bg-gradient-to-b from-blue-100 to-blue-50 border-b-4 border-red-700">
    <div className="flex items-center justify-between">
      <span className="text-sm font-bold text-dark tracking-wide uppercase">LUCY</span>
      <span className="text-xs font-medium text-blue-900 bg-blue-50 px-2 py-0.5 rounded-full">PAUSED</span>
    </div>
  </div>
  <div className="aspect-[4/3] bg-black relative">
    {/* Dimmed last frame */}
    <div className="absolute inset-0 bg-black/40 flex flex-col items-center justify-center gap-3">
      <div className="w-16 h-16 border-3 border-blue-300 bg-blue-100 rounded-full flex items-center justify-center">
        <span className="text-3xl">⏸</span>
      </div>
      <button className="px-4 py-1.5 bg-lego-blue text-white text-xs font-bold rounded-md hover:bg-blue-700 transition-colors"
              aria-label="Resume stream for LUCY">
        Resume
      </button>
    </div>
  </div>
</div>
```

### 7. Selected

User has clicked/focused this card for expanded controls. This is an overlay state applied on top of another state (typically Streaming).

| Property | Value | Tailwind |
|----------|-------|----------|
| **Border** | 3px solid `#0055BF` (Lego Blue) + outer glow | `border-3 border-lego-blue` |
| **Background** | White `#FFFFFF` (underlying state bg) | `bg-white` |
| **Text color** | Inherits from underlying state | — |
| **Icon** | Checkmark ✓ (in badge area) | — |
| **Animation** | Glow pulse 1.5s ease — blue box-shadow | Custom `shadow-[0_0_20px_rgba(0,85,191,0.5)]` |
| **Interaction** | Expanded controls panel below card; keyboard shortcuts active for this card | Full controls |
| **Status badge** | Underlying state badge + blue `SELECTED` overlay | — |
| **Glow** | `box-shadow: 0 0 0 2px #FFD700, 0 0 20px rgba(0, 85, 191, 0.5)` | Custom |
| **Ring** | Outer ring: 4px blue with 2px green offset | `ring-4 ring-blue-400 ring-offset-2 ring-offset-green-500` |

```jsx
{/* Selected state — applied as overlay on any other state */}
<div className="border-3 border-lego-blue bg-white rounded-lg overflow-hidden cursor-pointer 
                ring-4 ring-blue-400 ring-offset-2 ring-offset-green-500
                shadow-[0_0_0_2px_#FFD700,0_0_20px_rgba(0,85,191,0.5)]
                transition-all duration-300">
  {/* Inner content from underlying state (e.g., Streaming) */}
  
  {/* Expanded controls panel — only shown when selected */}
  <div className="p-3 bg-gradient-to-b from-blue-50 to-white border-t-2 border-blue-200">
    <div className="flex items-center justify-between">
      <span className="text-xs font-bold text-blue-900">CONTROLS</span>
      <span className="text-xs text-green-700 bg-green-50 px-2 py-0.5 rounded-full">✓ SELECTED</span>
    </div>
    <div className="mt-2 flex gap-2">
      <button className="flex-1 px-3 py-1 bg-lego-blue text-white text-xs font-bold rounded-md">Fullscreen</button>
      <button className="flex-1 px-3 py-1 bg-lego-yellow text-black text-xs font-bold rounded-md">Snapshot</button>
      <button className="flex-1 px-3 py-1 bg-lego-red text-white text-xs font-bold rounded-md">Restart</button>
    </div>
  </div>
</div>
```

---

## State Transition Matrix

```
                   ┌─────────┐
                   │ Offline  │
                   └────┬─────┘
                        │ pod scheduled
                        ▼
                   ┌─────────┐
                   │ Loading  │
                   └────┬─────┘
                        │ QEMU started, handshake begins
                        ▼
                   ┌───────────┐
                   │ Connecting│
                   └────┬──────┘
                        │ stream established
                        ▼
                   ┌───────────┐
              ┌───▶│ Streaming │◀───┐
              │    └─┬───────┬─┘    │
              │      │       │      │
              │ resume  pause  retry│
              │      │       │      │
              │      ▼       ▼      │
              │ ┌────────┐ ┌─────┐  │
              └─│ Paused │ │Error│──┘
                └────────┘ └─────┘

        Any state ──▶ Selected (overlay, user click)
        Any state ──▶ Error (on failure)
        Error ──▶ Loading (on retry)
```

---

## Responsive Sizing

### Mobile (< 640px)

| Property | Value |
|----------|-------|
| Card width | 100% (full-width, single column) |
| Card padding | `p-3` (12px) |
| Stream viewport | 4:3 aspect, full card width |
| Font sizes | Name: `text-sm`, Status: `text-xs`, Badge: `text-[10px]` |
| Controls | Stacked vertically |
| Grid gap | `gap-4` (16px) |

### Tablet (640–1023px)

| Property | Value |
|----------|-------|
| Card width | Min 280px, 2-column grid |
| Card padding | `p-4` (16px) |
| Stream viewport | 4:3 aspect |
| Font sizes | Name: `text-base`, Status: `text-sm`, Badge: `text-xs` |
| Controls | Horizontal row |
| Grid gap | `gap-6` (24px) |

### Desktop (≥ 1024px)

| Property | Value |
|----------|-------|
| Card width | Min 300px, 3-column grid (3×3 for 9 instances) |
| Card padding | `p-4` (16px), `p-6` (24px) on selected |
| Stream viewport | 4:3 aspect |
| Font sizes | Name: `text-lg`, Status: `text-sm`, Badge: `text-xs` |
| Controls | Horizontal row with expanded panel on selected |
| Grid gap | `gap-8` (32px) |
| Max width | `max-w-[1440px] mx-auto` |

### Tailwind Responsive Classes

```html
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 
            gap-4 sm:gap-6 lg:gap-8 
            p-4 sm:p-6 
            max-w-[1440px] mx-auto">
  <!-- 9 InstanceCard components -->
</div>
```

---

## Design Token Summary

| Token | Loading | Connecting | Streaming | Error | Offline | Paused | Selected |
|-------|---------|------------|-----------|-------|---------|--------|----------|
| `--border-color` | `#FFD700` | `#FFD700` | `#00A651` | `#C4281C` | `#9E9E9E` | `#0055BF` | `#0055BF` |
| `--border-width` | 2px | 2px | 2px | 2px | 1px | 2px | 3px |
| `--bg` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | `#FFEBEE` | `#F5F5F5` | `#FFFFFF` | `#FFFFFF` |
| `--text` | `#F57F17` | `#1B1B1B` | `#1B1B1B` | `#B71C1C` | `#9E9E9E` | `#0D47A1` | inherit |
| `--icon` | ⚡ skeleton | 🔄 spinner | 🟢 live dot | ⚠️ triangle | — dash | ⏸ pause | ✓ check |
| `--animation` | pulse | spin | pulse | none | none | none | glow |
| `--interactive` | no | click | full | retry | no | resume | full+ |

## References

- [Design System](design-system.md) — color palette, typography, spacing
- [InstanceCard.jsx](../../../frontend/src/components/InstanceCard.jsx) — current implementation
- [App.jsx](../../../frontend/src/App.jsx) — grid layout
- [Accessibility Audit](2026-03-27-accessibility-audit.md) — ARIA and focus requirements
