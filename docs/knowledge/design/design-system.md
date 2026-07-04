# Lego Design System

**Date**: 2026-03-27
**Author**: @design-lead
**Task**: D1
**Status**: finding

## Summary

Core design tokens, component specifications, and accessibility guidelines for the Lego Loco Cluster UI. This system governs the frontend dashboard (React + Tailwind), instance cards, stream viewers, and VR scene chrome.

---

## Color Palette

### Primary Lego Colors

| Name | Hex | RGB | Tailwind Class | CSS Variable | Usage |
|------|-----|-----|---------------|-------------|-------|
| Lego Green | `#00A651` | 0, 166, 81 | `text-lego-green` / `bg-lego-green` | `--color-lego-green` | Success states, healthy/active instances, streaming indicator |
| Lego Red | `#C4281C` | 196, 40, 28 | `text-lego-red` / `bg-lego-red` | `--color-lego-red` | Error states, offline instances, critical alerts |
| Lego Yellow | `#FFD700` | 255, 215, 0 | `text-lego-yellow` / `bg-lego-yellow` | `--color-lego-yellow` | Warning states, connecting/loading, pending actions |
| Lego Blue | `#0055BF` | 0, 85, 191 | `text-lego-blue` / `bg-lego-blue` | `--color-lego-blue` | Primary actions, selected state, links, focus indicator |

**Usage guidelines**:
- Green and Red are reserved for status communication — never use them decoratively
- Yellow is a warning color; avoid using it for non-status elements due to low contrast on white
- Blue is the primary interactive color (buttons, links, selected borders)
- Never use Lego brand colors for large background fills — use neutrals instead

### Neutral Colors

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| White | `#FFFFFF` | 255, 255, 255 | Card backgrounds, content areas |
| Light Gray | `#F5F5F5` | 245, 245, 245 | Page background, disabled card background |
| Medium Gray | `#9E9E9E` | 158, 158, 158 | Disabled text, muted elements, placeholder text |
| Dark Gray | `#616161` | 97, 97, 97 | Secondary text, subtle labels |
| Dark | `#1B1B1B` | 27, 27, 27 | Primary text, headers, high-contrast elements |

### Status Colors (Extended)

| Status | Background Tint | Border | Text | Contrast Ratio (on white) |
|--------|----------------|--------|------|--------------------------|
| Healthy / Streaming | `#E8F5E9` | `#00A651` | `#1B5E20` | 7.2:1 ✅ |
| Warning / Connecting | `#FFF8E1` | `#FFD700` | `#F57F17` | 3.1:1 (use dark text) |
| Error / Offline | `#FFEBEE` | `#C4281C` | `#B71C1C` | 5.8:1 ✅ |
| Info / Selected | `#E3F2FD` | `#0055BF` | `#0D47A1` | 7.5:1 ✅ |
| Neutral / Paused | `#F5F5F5` | `#9E9E9E` | `#616161` | 4.6:1 ✅ |

---

## Typography

### Font Stack

| Usage | Font Family | Fallback | Weight | Tailwind Class |
|-------|-----------|----------|--------|---------------|
| **Win98 Aesthetic** (instance labels, terminal text) | `"MS Sans Serif"`, `"Fixedsys"` | `"Courier New"`, monospace | 400 | `font-win98` |
| **Modern UI** (headers, navigation) | `"Inter"`, `"Segoe UI"` | `system-ui`, `-apple-system`, sans-serif | 600–700 | `font-sans font-semibold` |
| **Body Text** | `"Inter"`, `"Segoe UI"` | `system-ui`, sans-serif | 400 | `font-sans` |
| **Monospace** (IPs, ports, code) | `"JetBrains Mono"`, `"Fira Code"` | `"Courier New"`, monospace | 400 | `font-mono` |

### Type Scale

| Element | Size | Line Height | Weight | Tailwind |
|---------|------|-------------|--------|----------|
| H1 — Page title | 24px (1.5rem) | 32px | 700 (bold) | `text-2xl font-bold` |
| H2 — Section header | 20px (1.25rem) | 28px | 600 (semibold) | `text-xl font-semibold` |
| H3 — Subsection | 18px (1.125rem) | 24px | 600 | `text-lg font-semibold` |
| Body | 16px (1rem) | 24px | 400 | `text-base` |
| Small / Caption | 14px (0.875rem) | 20px | 400 | `text-sm` |
| Instance label | 18px (1.125rem) | 24px | 600 | `text-lg font-semibold` |
| Monospace values | 14px (0.875rem) | 20px | 400 | `font-mono text-sm` |
| Status badge | 12px (0.75rem) | 16px | 500 (medium) | `text-xs font-medium` |

---

## Spacing Scale

Base unit: **4px**. All spacing derives from multiples of 4.

| Token | Value | Tailwind | Usage |
|-------|-------|----------|-------|
| `space-1` | 4px | `p-1`, `m-1` | Tight inner padding (badge) |
| `space-2` | 8px | `p-2`, `m-2`, `gap-2` | Icon-to-text gap, inline spacing |
| `space-3` | 12px | `p-3`, `m-3` | Compact card padding |
| `space-4` | 16px | `p-4`, `m-4`, `gap-4` | Standard card gap, section margin |
| `space-6` | 24px | `p-6`, `m-6` | Card internal padding |
| `space-8` | 32px | `p-8`, `m-8` | Section spacing |
| `space-12` | 48px | `p-12` | Page header vertical padding |
| `space-16` | 64px | `p-16` | Major section separation |

### Border Radius
| Element | Radius | Tailwind |
|---------|--------|----------|
| Card | 8px | `rounded-lg` |
| Button | 6px | `rounded-md` |
| Badge | 9999px (pill) | `rounded-full` |
| Stream viewer | 4px | `rounded` |

---

## Instance Card States

7 states with distinct visual treatment:

| # | State | Border Color | Border Width | Background | Icon | Animation | Description |
|---|-------|-------------|-------------|------------|------|-----------|-------------|
| 1 | **Loading** | `#FFD700` Yellow | 2px | White | Skeleton placeholder | Pulse shimmer | Instance pod starting, QEMU booting |
| 2 | **Connecting** | `#FFD700` Yellow | 2px | White | Spinning circle | Rotate 1s linear | VNC/WebRTC handshake in progress |
| 3 | **Streaming** | `#00A651` Green | 2px | White | Green live dot (⬤) | Pulse 2s ease | Active video stream from QEMU |
| 4 | **Error** | `#C4281C` Red | 2px | `#FFEBEE` light red | Error triangle (⚠) | None | QEMU crashed, VNC unreachable, health check failed |
| 5 | **Offline** | `#9E9E9E` Gray | 1px | `#F5F5F5` light gray | Dash (—) | None | Pod not running, no instance detected |
| 6 | **Paused** | `#0055BF` Blue | 2px | White | Pause icon (⏸) | None | Stream paused by user, QEMU still running |
| 7 | **Selected** | `#0055BF` Blue | 3px + glow | White | Checkmark (✓) | Glow pulse 1.5s | User has selected this card for focus/action |

### Card State Transitions
```
Offline → Loading → Connecting → Streaming
                                     ↕
                                   Paused
                 Any → Error
         Error → Loading (on retry)
        Any → Selected (user click, overlay on other state)
```

---

## Responsive Grid

### Layout: 3×3 Instance Grid

| Breakpoint | Name | Columns | Card Min Width | Container |
|-----------|------|---------|----------------|-----------|
| < 640px | Mobile | 1 | 100% | Full width, `px-4` |
| 640–767px | Small tablet | 2 | 280px | `max-w-2xl mx-auto` |
| 768–1023px | Tablet | 2 | 320px | `max-w-4xl mx-auto` |
| ≥ 1024px | Desktop | 3 | 300px | `max-w-6xl mx-auto` |
| ≥ 1440px | Wide | 3 | 380px | `max-w-[1440px] mx-auto` |

### Grid CSS
```css
.instance-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 1rem; /* gap-4 */
  padding: 1.5rem; /* p-6 */
  max-width: 1440px;
  margin: 0 auto;
}
```

### Tailwind Implementation
```html
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 p-6 max-w-[1440px] mx-auto">
  <!-- 9 InstanceCard components -->
</div>
```

---

## Component Specs

### Card

The primary UI element — one per QEMU instance.

| Property | Value |
|----------|-------|
| Width | Fluid (min 280px, max 1fr) |
| Padding | `p-6` (24px) |
| Border | 2px solid (color by state) |
| Border radius | `rounded-lg` (8px) |
| Background | White (`#FFFFFF`), tinted in error/offline states |
| Shadow | `shadow-sm` default, `shadow-lg` on hover/selected |
| Transition | `transition-all duration-200` |

**Structure**:
```
┌─────────────────────────────────┐
│ [StatusBadge]  LOCO-0N     [⋮] │  ← Header row
│                                  │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │     StreamViewer            │ │  ← 16:9 aspect ratio
│ │     (VNC/WebRTC frame)      │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                  │
│ IP: 192.168.10.1X   VNC: 590X  │  ← Footer metadata (mono font)
└─────────────────────────────────┘
```

### Header

Page-level header bar.

| Property | Value |
|----------|-------|
| Height | 64px (`h-16`) |
| Background | `#1B1B1B` dark |
| Text color | White |
| Padding | `px-6` |
| Logo | Lego brick icon + "Loco Cluster" text |
| Right side | Status summary (X/9 online), settings gear icon |
| Position | `sticky top-0 z-50` |
| Border bottom | 3px solid `#C4281C` Lego Red accent line |

### StatusBadge

Pill-shaped badge indicating instance state.

| Property | Value |
|----------|-------|
| Height | 24px |
| Padding | `px-2 py-0.5` |
| Border radius | `rounded-full` (pill) |
| Font | `text-xs font-medium uppercase` |
| Background | Status tint color (from status colors table) |
| Text | Status border color (ensures contrast) |
| Min width | 72px (prevents layout shift between states) |

**Badge labels**: `LOADING`, `CONNECTING`, `STREAMING`, `ERROR`, `OFFLINE`, `PAUSED`, `SELECTED`

### StreamViewer

The embedded video/VNC viewport within each card.

| Property | Value |
|----------|-------|
| Aspect ratio | 4:3 (Win98 native at 1024×768) |
| Background | `#000000` (black, visible before stream loads) |
| Border radius | `rounded` (4px) |
| Overflow | `hidden` |
| Placeholder | Skeleton shimmer during Loading state |
| Error state | Red-tinted overlay with error icon |
| Click action | Expand to fullscreen stream view |
| Resize | `object-contain` (preserves Win98 aspect ratio) |

---

## Accessibility (WCAG 2.1 AA)

### Contrast Ratios

All text must meet WCAG 2.1 AA minimum contrast ratios:
- **Normal text** (< 18px): 4.5:1 minimum
- **Large text** (≥ 18px bold or ≥ 24px): 3:1 minimum
- **UI components** (borders, icons): 3:1 minimum

| Element | Foreground | Background | Ratio | Pass? |
|---------|-----------|-----------|-------|-------|
| Body text | `#1B1B1B` | `#FFFFFF` | 17.4:1 | ✅ AA + AAA |
| Secondary text | `#616161` | `#FFFFFF` | 5.9:1 | ✅ AA |
| Green status text | `#1B5E20` | `#E8F5E9` | 7.2:1 | ✅ AA + AAA |
| Red status text | `#B71C1C` | `#FFEBEE` | 5.8:1 | ✅ AA |
| Blue link text | `#0055BF` | `#FFFFFF` | 7.3:1 | ✅ AA + AAA |
| Yellow warning text | `#F57F17` | `#FFF8E1` | 3.1:1 | ⚠️ Large text only |
| Disabled text | `#9E9E9E` | `#FFFFFF` | 2.8:1 | ❌ Decorative only |
| Header text | `#FFFFFF` | `#1B1B1B` | 17.4:1 | ✅ AA + AAA |

**Note**: Yellow warning text (`#F57F17` on `#FFF8E1`) does not meet AA for normal text. Use `#B8860B` (`--color-warning-text-dark`) for small warning labels to achieve 4.5:1.

### Focus Indicators

All interactive elements must have visible focus indicators:

```css
/* Global focus style */
:focus-visible {
  outline: 3px solid #0055BF;  /* Lego Blue */
  outline-offset: 2px;
  border-radius: 4px;
}

/* Card focus — elevated ring */
.instance-card:focus-visible {
  box-shadow: 0 0 0 3px #0055BF, 0 0 0 5px rgba(0, 85, 191, 0.3);
  outline: none;
}
```

- Focus ring: 3px solid Lego Blue with 2px offset
- Cards: Blue box-shadow ring (visible on all background colors)
- Buttons: Standard outline + background shift
- Never remove focus styles — only enhance them

### Screen Reader Labels

| Component | `aria-label` / `aria-labelledby` | `aria-live` | `role` |
|-----------|--------------------------------|-------------|--------|
| Instance Card | `"Instance LOCO-0N, status: {state}"` | — | `article` |
| StatusBadge | `"{state} status"` | `polite` (on change) | `status` |
| StreamViewer | `"Video stream for instance LOCO-0N"` | — | `img` |
| Instance Grid | `"Emulator instances, {X} of 9 online"` | `polite` | `region` |
| Header | — | — | `banner` |
| Fullscreen button | `"View instance LOCO-0N fullscreen"` | — | `button` |
| Settings menu | `"Instance LOCO-0N actions"` | — | `menu` |

### Keyboard Navigation

| Key | Action |
|-----|--------|
| Tab | Move focus between cards (grid navigation) |
| Enter / Space | Select focused card / activate button |
| Escape | Exit fullscreen / close menu |
| Arrow keys | Navigate within card actions or menu |

Cards should be focusable (`tabindex="0"`) and respond to Enter for selection.

---

## Tailwind Config Extensions

Add to `tailwind.config.js`:

```js
module.exports = {
  theme: {
    extend: {
      colors: {
        'lego-green': '#00A651',
        'lego-red': '#C4281C',
        'lego-yellow': '#FFD700',
        'lego-blue': '#0055BF',
        'dark': '#1B1B1B',
      },
      fontFamily: {
        'win98': ['"MS Sans Serif"', '"Fixedsys"', '"Courier New"', 'monospace'],
      },
    },
  },
}
```

---

## References

- [Frontend source](../../../frontend/src/) — React components
- [Tailwind config](../../../frontend/tailwind.config.js) — current theme configuration
- [Instance Identity Spec](../lan-networking/instance-identity-spec.md) — instance naming for labels
- WCAG 2.1 AA: https://www.w3.org/WAI/WCAG21/quickref/
