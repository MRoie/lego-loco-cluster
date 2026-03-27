# Lego Design System

**Date**: 2025-01-24
**Author**: @design-lead
**Task**: D1
**Status**: finding

## Summary
Core design tokens and component specifications for the Lego Loco Cluster UI.

## Color Palette

### Primary Lego Colors
| Name | Hex | RGB | Tailwind Class | Usage |
|------|-----|-----|---------------|-------|
| Lego Green | `#00A651` | 0, 166, 81 | `text-lego-green` | Success, healthy, active |
| Lego Red | `#C4281C` | 196, 40, 28 | `text-lego-red` | Error, offline, critical |
| Lego Yellow | `#FFD700` | 255, 215, 0 | `text-lego-yellow` | Warning, connecting, pending |
| Lego Blue | `#0055BF` | 0, 85, 191 | `text-lego-blue` | Primary, selected, links |

### Neutral Colors
| Name | Hex | Usage |
|------|-----|-------|
| White | `#FFFFFF` | Card backgrounds, content areas |
| Light Gray | `#F5F5F5` | Page background |
| Medium Gray | `#9E9E9E` | Disabled, muted elements |
| Dark | `#1B1B1B` | Text, headers |

## Instance Card States

| State | Border Color | Background | Icon | Animation |
|-------|-------------|------------|------|-----------|
| Loading | Yellow | White | Skeleton | Pulse shimmer |
| Connecting | Yellow | White | Spinner | Rotate |
| Streaming | Green | White | Live dot | Pulse |
| Error | Red | Light red tint | Error icon | None |
| Offline | Gray | Light gray | Dash | None |
| Paused | Blue | White | Pause icon | None |
| Selected | Blue + glow | White | Check | Glow pulse |

## Grid Layout
- 3×3 grid for 9 instances
- Responsive: 1 col (mobile < 640px), 2 col (tablet 640-1024px), 3 col (desktop > 1024px)
- Card gap: `gap-4` (1rem)
- Card padding: `p-6` (1.5rem)
- Max container: 1440px centered

## Typography
- Headers: `font-bold`, sizes h1=2xl, h2=xl, h3=lg
- Body: `text-base` (16px)
- Monospace for technical values: `font-mono text-sm`
- Instance labels: `font-semibold text-lg`
