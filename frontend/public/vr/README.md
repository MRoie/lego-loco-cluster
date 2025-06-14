# VR Prototype

This folder contains a minimal A-Frame demo showing how the Lego Loco streams can be displayed in VR. It fetches `/api/config/instances` to determine how many streams exist and arranges them in a grid accordingly. If the request fails, it falls back to placeholder videos. Click a tile to zoom and focus it. A volume slider for the active tile appears in the top left corner. Keyboard events are logged to the console to illustrate how KVM focus could be routed to the selected instance.

## Running

Serve the folder with any static web server. For example:

```bash
npx serve frontend/public/vr
```

Then open the printed URL in your browser. You can also load `index.html` directly in GitHub Codespaces using the "Preview" feature.

This is only a mockup and does not connect to the backend yet.
