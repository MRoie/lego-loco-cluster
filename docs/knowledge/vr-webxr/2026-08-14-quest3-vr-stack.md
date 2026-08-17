# The VR path: Quest 3 → LEGO LOCO

How a headset on the LAN reaches the Windows 98 guests, what each control does,
and the defects that had to fall before any of it worked. Written after two
live Quest 3 review sessions and the fix rounds they drove.

## Entry point

**`https://192.168.1.18:6080`** — HTTPS is not optional: WebXR requires a
secure context, so `navigator.xr` does not exist on the plain-HTTP port and
immersive mode can never start there. The TLS listener is a second nginx
server block in the frontend image (self-signed cert, SAN covers the LAN IP,
generated at container start; a mounted `kubernetes.io/tls` Secret overrides
it), exposed on nodePort 30080 over the kind `6080` host mapping that the old
websockify setup left behind. Accept the certificate warning once per browser
(`CN=lego-loco-local`). Desktop keeps using `http://localhost:3000` —
localhost is already a secure context.

The LAN IP is a DHCP lease. If the router reassigns it, the URL moves and the
cert SAN is stale — a router reservation for this machine avoids both.

## Controls

| input | action |
|---|---|
| laser hover | guest cursor tracks the ray continuously (~30 Hz) |
| trigger (or hand-tracking pinch) | left click — discrete down/up edges, drags work |
| grip or B | **right click** |
| right stick up/down | scroll wheel, one notch per flick, auto-repeat held |
| **left stick fwd/back** | move the screen wall closer / farther (0.6–4.5 m) |
| **left stick left/right** | shrink / grow the wall (0.5×–2.2×) |
| A / X / Y | F1 / F3 / F4 (configurable; Y also toggles the menu) |

Wall distance and scale persist per browser (localStorage). The camera-locked
HUD line shows the active tile, VNC connection count, audio state, and the
current wall transform.

Audio unlocks on entering VR or the first trigger/grip press — the DOM
"Enable Audio" button does not exist inside immersive mode, so the unlock has
to ride gestures the headset can still deliver.

## Architecture

```
Quest browser (Wolvic / Meta Chrome)
  A-Frame scene (bundled, no CDN)
    tile plane ← THREE.CanvasTexture ← noVNC canvas ← wss /proxy/vnc/<id>/
    spatial audio ← AudioWorklet ← wss /proxy/audio/<id>/ (raw PCM s16le 48k)
    vnc-laser-input (one component owns the RFB button mask, emits UV events)
    vnc-canvas-refresh (per-tile tick marks the texture dirty on the XR clock)
  nginx TLS :3443 (nodePort 30080 → host 6080)
    → backend WS↔TCP bridges (VNC :5901, audio :5902, setNoDelay)
      → per-pod: Xvnc / pulseaudio null-sink ← PCem ← Windows 98 + LOCO
```

The pointer end-to-end was certified before the headset ever connected:
pixel-exact tracking through the same WebSocket route (match score 0.0000,
gain 1.000/1.000, zero drift), motion-to-update p50 112 ms server-side.

## The defects, so nobody re-earns them

Every one of these presented as "VR is broken" and had a specific cause.

1. **White screen on the VR button, every browser.** A `useEffect` deps array
   referenced consts declared 235 lines later — TDZ throw on first render, no
   error boundary, React 18 unmounted the entire root. Nothing to do with VR:
   desktop white-screened identically. There is now a `VRErrorBoundary`, and
   the reproduction technique (headless Chromium driven over CDP by a stdlib
   python WS client) lives on in scratch as the standard way to verify this
   app without a headset.
2. **Clicks "inconsistent", right-click missing.** The VR viewer component
   was scaffold that never connected; the trigger was also bound as the Enter
   key; and the underlying send called `rfb.sendPointerEvent`, which does not
   exist in noVNC 1.7 — its TypeError was swallowed by a try/catch that then
   logged "sent". Input is rebuilt on discrete edge events only, and the
   pointer API uses the protocol-level `RFB.messages.pointerEvent`.
3. **Black tiles with colored circles.** The VNC canvas was set as an
   `a-asset-item` attribute — a DOM object stringifies to
   `[object HTMLCanvasElement]`, so the texture pointed at nothing; the
   circles were the audio rings over untextured planes. Tiles now get a
   `THREE.CanvasTexture` on the mesh directly (linear filter, no mipmaps —
   1024×768 is NPOT).
4. **Green void, content unreachable.** Two bugs reading as one: the rig
   baked in 1.6 m of height *on top of* the headset's local-floor height
   (eyes at ~3.3 m, screens at the user's feet), and the sky was an all-green
   sphere with nothing else in the world — no horizon to orient by. Rig sits
   at the floor now; the camera keeps 1.6 for desktop only.
5. **Video fluid on web, frozen in VR.** The texture refresh rode
   `window.requestAnimationFrame`, which stops when an immersive session
   starts — rendering moves to the XR session's own clock. The refresh now
   lives in an A-Frame component `tick`, which follows whichever clock is
   driving the scene.
6. **"Booting" forever on running instances.** `/api/status` served a static
   config file. It now derives status from each emulator's own health
   endpoint (5 s cache), and the tile label additionally yields to observed
   reality: a live texture means the guest is not booting, whatever any feed
   says.
7. **Nothing could be moved.** The rig carried `movement-controls` — a
   component from a library (`aframe-extras`) this app has never shipped. An
   unregistered A-Frame component is silently inert. The wall transform
   controls replace it.
8. **No stats in-headset.** DOM overlays cease to exist in immersive mode.
   Anything the user must see in VR has to be an in-scene entity; anything
   they must click has to be reachable by controller events.

## Verifying without a headset

Headless Chromium (`chromedp/headless-shell`, `--network=host --shm-size=2g`)
driven over CDP: load the page, DOM-click `.lego-vr-button`, then interrogate
the live scene — `el.getObject3D('mesh').material.map.isCanvasTexture`, pixel
sweeps of the texture canvases, entity positions, HUD text, and
`Runtime.exceptionThrown` for the whole session. Driver scripts:
`/run/media/r/R/DockerData/pcem-work/cdp-vr-*.py`. What headless cannot judge:
immersive comfort, controller feel, and the cert-acceptance flows — those
need the headset.

Do not trust `map.constructor.name` in production bundles (THREE is minified;
the name is junk) — use the `isCanvasTexture` flag. And do not measure the
guest cursor by frame-differencing; LOCO's menu animates. Template-match with
`scripts/cursor-locate.py`.

## Known limits

- Immersive entry, controller ergonomics and spatial-audio placement have not
  yet had a passing on-headset review since these fixes; everything above is
  machine-verified except feel.
- The 2×2 four-instance layout is machine-verified live: four tiles at
  (±0.775, ±0.575), all four textures >98% non-black, active pop-out clearing
  every neighbour (needs 1.248/0.936, spacing gives 1.550/1.150), HUD at
  `vnc 4/4`. On-headset review still pending.
- A ninth defect for the list: the VR scene read its instance list from
  `/api/config/instances`, a static two-entry config file, while the grid
  used live discovery — scaling the cluster changed the grid and not VR.
  Same fossil-config failure as `/api/status`; both now derive from the
  cluster.
- WebRTC console noise ("Peer connection lost") is the dormant QEMU-flavor
  video path retrying; the VNC canvas path the tiles actually use is
  unaffected.
