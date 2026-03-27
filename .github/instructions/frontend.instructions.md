---
description: "Use when editing frontend React components, Tailwind styles, Vite config, or dashboard layout. Covers React 19 patterns, Lego design system, and component conventions."
applyTo: "frontend/**"
---
# Frontend Development Guidelines

## React Patterns
- Use functional components with hooks (no class components)
- State management via ActiveContext provider (`ActiveContext.jsx`)
- Custom hooks in `frontend/src/hooks/` for reusable logic
- Lazy-load heavy components with `React.lazy()` and `Suspense`

## Lego Design System
- Colors: Green #00A651 (success), Red #C4281C (error), Yellow #FFD700 (warning), Blue #0055BF (primary)
- Use Tailwind classes from `tailwind.config.js` — custom Lego theme is configured
- 3×3 responsive grid: mobile (1 col), tablet (2 col), desktop (3 col)
- 7 card states: loading, connecting, streaming, error, offline, paused, selected

## Component Conventions
- One component per file in `frontend/src/components/`
- VR components prefixed with `VR` (e.g., `VRScene.jsx`, `VRControls.jsx`)
- Props: destructure in function signature
- Event handlers: prefix with `handle` (e.g., `handleClick`)

## Testing
- Run `cd frontend && npm run build` to verify no build errors
- Playwright E2E tests reference components by data-testid attributes

## Knowledge
- Document patterns in `docs/knowledge/frontend/`
