# Active Container Focus Plan

This document outlines the approach for minimizing resource usage by running
only focused emulator containers at full speed. The active state is now a list
of one or more container IDs that should receive input and full resources. This
list must be shared across the entire stack so the frontend, VR mode, backend
and Kubernetes cluster always agree which containers are active.

## Goals
- Synchronize the active container ID between the web UI, VR interface and backend.
- Scale CPU usage so unfocused containers run at reduced capacity or are paused.
- Provide UI controls to quickly switch focus and snap the cursor to the
  selected container.
- Allow optional multi-focus mode where several containers receive input and full
  resources.
- Keep deployment simple so the same images work locally and in clusters. A small
  VR menu lets the user pick the active instance directly while in headset.

## Implementation Outline
1. Extend `config/instances.json` or a new API endpoint to store `activeInstanceId`.
2. Add backend WebSocket events to broadcast focus changes in real time.
3. Update the React frontend and VR scene to highlight and control the active
   instance. When switching focus, the cursor snaps to the new container.
4. Introduce CPU quotas or pause logic in the emulator Docker container to reduce
   load when an instance is not focused.
5. Provide scripts or `kubectl` helpers to adjust pod resources in Kubernetes so
   only focused containers run at full speed.
6. Update tests to verify focus switching does not break streaming and that CPU
   usage drops for inactive containers.
7. Document configuration options for multi-focus mode and default quotas.

## Recent Updates
- A shared React `ActiveContext` now keeps the front-end and VR scene in sync
  with the backend WebSocket. Switching focus updates the context and broadcasts
  immediately.
- A new script `scripts/ev3_focus_ws.py` runs on an EV3 brick. The left and
  right buttons cycle through instances while the center button sends the
  selection to the backend. Holding the center button clears focus.
- Spatial audio in VR now reads the active list so only focused instances play
  at full volume. Up to nine instances are supported with per-tile volume
  controls.

## Future Work
The tasks below should be completed after the current milestones:
 - Implement the backend focus API and WebSocket notifications. **(done)**
 - Apply front‑end state management to react to focus changes. **(done)**
 - Add command line utilities for cluster operators to change the active instance. See `scripts/set_active.sh`. **(done)**
 - Create regression tests covering focus switching and resource scaling. **(added)**
 - Update Helm values and Docker Compose files with CPU limit examples. **(added)**
 - Expand documentation to include a walkthrough of the active container system. **(added)**

## API Usage
The backend exposes `/api/active` for getting and setting the focused instance. A WebSocket at `/active` broadcasts updates. Use `scripts/set_active.sh` to change focus from the command line.

## Walkthrough
1. A user selects an instance in the React dashboard, VR menu or via the EV3 helper. This triggers a POST request to `/api/active`.
2. The backend writes `config/active.json` and broadcasts the new ID to all WebSocket clients.
3. Frontend components subscribe via `ActiveContext`, keeping the web UI and VR scene in sync.
4. Spatial audio in the VR scene positions each emulator using the Web Audio API. The focused instance plays at full volume while others are dimmed and can be adjusted individually.
5. `scripts/set_active.sh` may be run manually. It updates the config, annotates Kubernetes pods and adjusts Docker CPU quotas so the focused container runs with `FOCUSED_CPUS` while others use `UNFOCUSED_CPUS`.
6. Helm and Docker Compose set default CPU limits which the script tweaks dynamically.
