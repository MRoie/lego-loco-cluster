# Standalone qemu-3dfx headless test — running LEGO LOCO's 3D for the Loco Lens

Bring-up log + reproducible scripts for getting **LEGO LOCO's Direct3D intro/menu
to actually render** in a headless container, so the Loco Lens can stream real
gameplay (not just the Win98 desktop). This is the "game source" side of the
lens; the watch/firmware side is in [../../../m5stack-lens/docs/](../../../m5stack-lens/docs/).

## TL;DR
- LEGO LOCO uses Direct3D. Under plain QEMU it **GPFs or hard-hangs** because the
  in-guest **software SoftGPU** rasterizer can't complete its 3D.
- The fix is **qemu-3dfx** (kjliew/qemu-3dfx): a QEMU fork with **Mesa/Glide
  pass-through** that forwards the guest's GL to the *host's* OpenGL.
- Built here (`build-qemu3dfx.sh`) + run headless (`run-3dfx-headless.sh`):
  LOCO's 3D **renders correctly and animates** where software SoftGPU froze.
- On a **GPU-less Windows/Docker/WSL2 host** the host GL is software `llvmpipe`,
  so it's correct-but-slow (~1 frame/90 s). Fluid play needs a **GPU-backed GL**
  (real GPU + `/dev/dxg`/d3d12, or a Linux host with GPU + KVM).

## The journey (what was tried, what each proved)

| Attempt | Result |
|---|---|
| `win98-loco-golden-safe512` + `-vga std` | LOCO **GPF on launch** (no 3D path) |
| `netready.qcow2` (SoftGPU) + `-vga vmware`, `-cpu pentium3` | intro renders then **GPFs at menu** (SSE-less CPU) |
| + `-cpu qemu32,+sse3,+ssse3,+sse4.1` | boots/runs; SoftGPU rasterizer needs the SIMD |
| + `-accel tcg,thread=multi` (MTTCG) | **hangs** early (MTTCG race in this guest) |
| + `-accel tcg` (single-thread) | **got furthest** — intro animates to the swarm, then still hangs |
| + `-device sb16` (ISA) | boots fine *with qemu32* (Pentium3 hung on it); not the fix |
| **conclusion** | software SoftGPU **cannot** complete LOCO's 3D at any flag setting |
| **`qemu-3dfx` (Mesa passthrough)** | LOCO 3D **renders + progresses** (llvmpipe host GL); correct but slow without a GPU |

Other findings along the way:
- **Guest mouse is relative (PS/2)** under the software path → VNC absolute
  clicks miss. Add `-device usb-tablet` for absolute mouse (needed for the lens
  to inject clicks that land). Under the 3dfx path the guest runs at **640×480**.
- **Lens color bug (red↔blue):** QEMU VNC is 32bpp little-endian **BGRX**; the
  framebuffer blit copied bytes straight as RGB. Fixed in
  [`backend/services/rfbFramebuffer.js`](../../../backend/services/rfbFramebuffer.js)
  by honouring the negotiated channel offsets. Verified: red LEGO logo/bricks.
- **`LENS_CROP_SIZE`** now honoured (default 466, 1:1 with the 468px watch panel).

## Scripts

Both run against the SoftGPU golden image at
`containers/qemu-softgpu/tmp-bake/netready.qcow2` and keep all build artifacts on
a separate drive (here `G:`), since the toolchain/build tree is multi-GB.

### `build-qemu3dfx.sh`  (run once, ~20–40 min)
Builds QEMU 9.2.2 + the qemu-3dfx Mesa/Glide patch into `/work/opt/qemu-3dfx`,
plus the headless-GL runtime (Xvfb, software Mesa/llvmpipe, x11vnc).
```sh
docker run -d --name qemu3dfx -v <BUILD_DIR>:/work \
  -v <REPO>/containers:/img:ro debian:bookworm-slim sleep infinity
docker exec -d qemu3dfx bash -c "bash /work/build.sh > /work/build.log 2>&1"
# wait for BUILD_OK in /work/build.log
```

### `run-3dfx-headless.sh`
Starts Xvfb :99 → forces `llvmpipe` → x11vnc bridges to VNC :5901 → boots the
golden image with qemu-3dfx `-display sdl,gl=on` (Mesa passthrough) + usb-tablet.
Capture/inject over VNC (published to host :5903 in testing).
```sh
docker exec -d qemu3dfx bash /work/run.sh
```

## Making it fluid (GPU)
On this host `/dev/dxg` (WSL2 GPU) was **not** exposed to the container, so Mesa
fell back to `llvmpipe`. To accelerate:
1. Enable Docker Desktop GPU support; get `/dev/dxg` + `/usr/lib/wsl/lib` into
   the container; then `GALLIUM_DRIVER=d3d12` uses the real GPU (the
   `d3d12_dri.so` driver ships in Debian mesa).
2. Or run qemu-3dfx on a **Linux host with a GPU + KVM** — its intended target.
