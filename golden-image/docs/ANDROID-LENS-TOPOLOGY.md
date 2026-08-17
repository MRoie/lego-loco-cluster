# Loco Lens on Android (no cluster)

On a phone there's no Kubernetes, no discovery, no React dashboard — just one
QEMU with its VNC. The lens taps that same VNC; the full game view is whatever
already shows it (Termux:X11 or a VNC viewer). The VNC *is* the front-end.

```
QEMU (Win98 + Lego Loco)
        │  VNC 127.0.0.1:5901
        ├────────────────────────► Termux:X11 / VNC viewer   ← full screen ("the front")
        │
        └──► lens-server (Node) ──/ws/lens/local──► M5Stack StopWatch
                 static registry:  local → 127.0.0.1:5901        (circular crop)
```

## Picking which instance the lens shows

Selection is identical to the cluster; only endpoint *resolution* differs
(static registry instead of k8s discovery). Two ways to pick:

1. **At connect time** — the watch opens `ws://<host>:3001/ws/lens/<id>`. That
   `<id>` is the selector. On a phone it's just `local`.
2. **At runtime** — the watch sends `{ "type": "instance.select", "id": "..." }`
   and the bridge re-points its RFB at the new instance (tears down the old
   framebuffer, connects the new one) and replies `{ "type": "instance.active", "id" }`.

Single-instance Android has one id (`local`), so selection is trivial — but the
same machinery scales if you run 2–3 local QEMUs on different VNC ports:

```
LENS_INSTANCES='local=127.0.0.1:5901,second=127.0.0.1:5902' node lens-server.js
```

## Running the minimal server

```bash
# Termux: pkg install nodejs
# from the repo (reuses backend/ lens modules):
node golden-image/android/lens-server.js
#   env: LENS_INSTANCES (registry), LENS_PORT (3001), VNC_PASSWORD
```

Dependencies are a small subset of the backend: `express`, `ws`, `rfb2`
(pure-JS RFB), and optionally `sharp` (arm64 prebuilt exists; falls back to raw
frames if absent). No `@kubernetes/client-node`, no WebRTC.

## Where this plugs into the cluster backend

The full backend uses the same `InstanceResolver`: set `LENS_INSTANCES` and it
runs in **static** mode (also handy for docker-compose / a single host);
otherwise it falls back to **k8s** discovery. So the watch, protocol, crop, and
`instance.select` behaviour are identical whether you're on a phone or a cluster
— only the resolver strategy changes.
