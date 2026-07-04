# Discovery Status Component Enhancement

**Date**: 2026-03-27  
**Author**: @frontend-lead  
**Component**: `frontend/src/components/DiscoveryStatus.jsx`

## Summary

Enhanced the `DiscoveryStatus` component to show real-time instance discovery status in the header toolbar area. The component is collapsible — a compact summary bar is always visible, and clicking it expands a detailed per-instance panel.

## Design

### Compact bar (always visible)
- Discovery mode indicator dot (green = Kubernetes, yellow = static)
- **"X of 9 instances"** count
- Mini progress bar (green at 100%, yellow >50%, red <50%)
- Ready badge showing how many instances are healthy
- Chevron to expand/collapse details

### Expanded panel
- **Instance dot grid**: 9 slots rendered as colored circles (filled = discovered, dashed border = empty). Each dot shows the first letter of the instance name and is color-coded by state.
- **Per-instance list**: 3-column grid showing name + state label for every discovered instance.
- **Footer**: discovery mode label, last-update timestamp, and manual refresh button.

## State-to-color mapping (Lego themed)

| State       | Color        | Tailwind class   |
|-------------|-------------|------------------|
| ready       | Green       | `bg-green-500`   |
| running     | Green       | `bg-green-500`   |
| connecting  | Yellow      | `bg-yellow-400`  |
| booting     | Yellow      | `bg-yellow-400`  |
| degraded    | Orange      | `bg-orange-500`  |
| error       | Red         | `bg-red-500`     |
| offline     | Gray        | `bg-gray-500`    |
| unknown     | Gray        | `bg-gray-500`    |

## Data flow

```
App.jsx
  └─ useEffect: fetchLiveInstances() every 5 s  ──►  /api/instances/live
       │                                                     │
       ├─ setInstances(data.instances)                       │
       └─ setDiscoveryStatus(data)  ─────►  <DiscoveryStatus status={data} />
                                              reads: mode, stats, instances, lastUpdate
```

The component also supports manual refresh via `POST /api/instances/refresh`, dispatching a `discoveryRefreshed` custom event so `App.jsx` reloads the instance list immediately.

## Integration point

Rendered in `App.jsx` inside the header area, next to the VR-mode toggle button. No changes were needed in `App.jsx` since the component was already imported and wired up — only the component internals were replaced.

## Dependencies

- React (useState)
- `../api/discovery` — `refreshDiscovery()`
- Tailwind CSS utility classes (consistent with the rest of the frontend)
