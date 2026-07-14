# End-to-End Acceptance Criteria

## Golden image
- `qemu-img check` passes.
- Three cold boots, three clean shutdowns.
- **No recurring hardware wizard**.
- Required devices resolved in Device Manager.
- **No ScanDisk after a clean shutdown**.
- Lego Loco launches; city loads; trains animate; scrolling usable;
  inspection magnifiers work; save/load works.
- 20-minute stability test passes.

## Host (checked by `tests/e2e.sh`, no proprietary media needed)
- QEMU process alive.
- QMP reports `running`.
- VNC accepts an RFB handshake.
- Serial log contains `LOCO_READY`.
- Termux:X11 and VNC can operate against the same QEMU process.

## Lens prototype
- Framebuffer obtained without OCR (raw RFB rectangles).
- Circular 400×400 crop produced (transparent corners).
- Encoded (PNG default; JPEG on a bandwidth budget).
- Stale frames dropped, not queued.
- Normalized pointer input injected through RFB.
- Stream and input provably target the same QEMU instance.

### Engineering targets (measure, don't assume)
- Lens frame age < 250 ms.
- Input round-trip < 150 ms.
- ~8–12 fps at 320²–466² JPEG.

## Current GHCR snapshot status (measured 2026-07-07)
`emulator-snapshot:hostgame` and `:joingame`:
- **byte-identical** (same SHA256) — host/join role is not baked into the disk.
- qcow2 valid, standalone, no corruption.
- Boot into **ScanDisk** (dirty shutdown) then a **PnP Monitor wizard** — they
  fail "no ScanDisk after clean shutdown" and "no recurring hardware wizard".
- They DO reach a 1024×768 Lego Loco desktop with a city loaded.

Re-baking per `DRIVER-INSTALL-CHECKLIST.md` steps 16–19 (clean shutdowns + seal)
is required to meet the golden-image bar, plus a runtime or disk-level
differentiation of the host vs join roles.
