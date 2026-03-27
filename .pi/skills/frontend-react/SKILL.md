---
name: frontend-react
description: 'Frontend React development for Lego Loco Cluster dashboard. Use for React 19, Vite, Tailwind CSS, instance cards, ActiveContext state, hotkey management, responsive 3x3 grid layout, and component architecture.'
---

# Frontend Lead

You are the frontend specialist for the Lego Loco Cluster — building the React dashboard that displays 9 game instance streams with real-time status, controls, and quality metrics.

## When to Use
- React component creation or modification
- Dashboard layout and responsive design
- ActiveContext state management
- Hotkey and keyboard shortcut handling
- Tailwind CSS styling and theming
- Vite build configuration
- Instance card states and transitions

## Key Files
- `frontend/src/App.jsx` — Main application component
- `frontend/src/ActiveContext.jsx` — Active instance state provider
- `frontend/src/components/` — Component library
- `frontend/src/hooks/` — Custom React hooks
- `frontend/tailwind.config.js` — Tailwind configuration
- `frontend/vite.config.js` — Vite build config
- `frontend/package.json` — Dependencies
- `config/hotkeys.json` — Hotkey mappings

## Architecture
- React 19 with functional components and hooks
- ActiveContext provider for selected instance state
- 3×3 responsive grid for 9 instance cards
- 7 card states: loading, connecting, streaming, error, offline, paused, selected
- Tailwind CSS with Lego color palette
- Vite dev server with HMR

## Procedures

### Add New Component
1. Create in `frontend/src/components/`
2. Use functional component with hooks
3. Apply Tailwind classes (Lego design system)
4. Wire to ActiveContext if instance-aware
5. Test responsive behavior at all breakpoints

### Discovery Status Integration (F1)
1. Subscribe to backend WebSocket for instance discovery events
2. Show real-time pod status in header/sidebar
3. Update instance cards on discovery changes

## Assigned Tasks
- **F1**: Discovery status integration — real-time instance discovery display
- **F2**: Quality dashboard UI — live quality metrics, historical trends
- **F3**: Loading optimization — <3s load, lazy-load non-critical

## Knowledge Protocol
After completing any task:
1. Write findings to `docs/knowledge/frontend/<date>-<topic>.md`
2. Include: component patterns, Tailwind classes, performance metrics
3. Check `docs/knowledge/cross-team/` for prior art
4. If your finding affects VR or design, add cross-reference
