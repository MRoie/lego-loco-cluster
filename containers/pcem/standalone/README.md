# Standalone PCem test — evaluating PCem/Voodoo3 for LEGO LOCO

Bring-up log for testing whether **PCem** (real period-hardware emulation,
software Voodoo3 dynarec) can run LEGO LOCO more smoothly than QEMU+SoftGPU or
qemu-3dfx. See [../../qemu-softgpu/standalone/README.md](../../qemu-softgpu/standalone/README.md)
for the QEMU-side investigation this follows on from.

## TL;DR
- Built **PCem v17** (official `sarah-walker-pcem/pcem` Linux source release —
  no prebuilt binary exists, so it's compiled: SDL2 + wxWidgets + OpenAL).
- Configured a **Socket 7 / Intel i430VX** board (`model=430vx`, real Award BIOS
  dump, ROM sourced from the 86Box community ROM set — same file, shared
  BIOS across emulator projects) with a **3dfx Voodoo3 3000** (`gfxcard=v3_3000`)
  on PCI, at 640×480 in a headless Xvfb + x11vnc bridge (same pattern as
  qemu-3dfx: see [`run-pcem-headless.sh`](run-pcem-headless.sh)).
- **Real Award BIOS POSTs successfully.** Voodoo3 shows up correctly on the PCI
  bus (`Vendor 121A Device 0005`, "Display Controller"). This proves PCem +
  Voodoo3 is a viable hardware target in principle.
- **Found and fixed a major false lead**: BIOS-Setup keyboard input looked
  extremely flaky (dropped keys, "IDE HDD AUTO DETECTION" appearing to hang
  forever). Root cause: **PCem's SDL window doesn't receive real keyboard input
  until its *mouse* is captured** (window title literally says "Click to
  capture mouse"), and x11vnc's synthetic pointer clicks don't trigger SDL's
  capture-on-click detection — only a real X11 `XTestFakeButtonEvent` does
  (`xdotool click`, not a VNC-injected click). Fixed with `xdotool windowfocus`
  + `xdotool click` once at session start; after that, keyboard input via VNC
  became 100% reliable, and "IDE HDD AUTO DETECTION" completes cleanly in one
  pass through all four drives — it was never actually looping, just silently
  dropping the keys sent to dismiss each step. See gotcha #8.
- **Exhaustively ruled out every config-level cause of the disk failure**:
  exact-matching file size to configured CHS, classic vs. LBA-style geometry,
  manually forcing `TYPE=User` in Standard CMOS Setup, CD-ROM presence
  (the ATAPI CD-ROM slot is always enumerated regardless of `cdrom_path`), and
  the video card (`v3_3000` vs. plain ISA `vga` — identical failure either
  way). **"Primary master hard disk fail" is unrelated to anything in
  `pcem.cfg`** — it reproduces identically no matter what's changed on our side.
  This points to a genuine bug in PCem v17's IDE/PIIX emulation or its
  raw-disk/minivhd read path for this specific chipset, not a config mistake.
  Windows 98 never actually booted under PCem in this session.

## Gotchas found (useful if picking this back up)

1. **No prebuilt PCem binary exists.** The GitHub release asset
   (`PCemV17Linux.tar.gz`) is a **source tarball** (autotools), not a binary.
   Build deps: `libsdl2-dev libwxgtk3.2-dev libasound2-dev libopenal-dev`
   (OpenAL is a **hard** requirement on Linux — configure fails without it,
   no `--without-openal` flag). See [`build-pcem.sh`](build-pcem.sh).

2. **ROMs aren't bundled** (`roms/<model>/roms.txt` placeholders only, for
   licensing reasons) — but the exact same BIOS dumps PCem expects by filename
   are in the 86Box community ROM set (`github.com/86Box/roms`), which *does*
   bundle real dumps (86Box + PCem often want byte-identical vendor BIOS files).
   Cross-referencing `mem_bios.c`'s `romfopen("430vx/55xwuq0e.bin", ...)` call
   against 86Box's `machines/430vx/55XWUQ0E.BIN` (same size, 128 KB) confirmed
   the match. Same trick got the Voodoo3 3000 video BIOS
   (`voodoo3_3000/3k12sd.rom`, from 86Box's `video/voodoo/3k12sd.rom`).

3. **On Linux, PCem's config/ROM root is `$HOME/.pcem/`, *not* the executable's
   own directory** (`get_pcem_path()` in `wx-sdl2.c` calls
   `wxFileName::GetHomeDir()` unconditionally on `__linux`). Set `HOME` to a
   writable dir before launching and place `roms/` there (a symlink works, but
   **only if the target path doesn't already exist as a directory** — `ln -sfn
   src dst` silently nests inside an existing `dst` directory instead of
   replacing it; PCem auto-creates `~/.pcem/{roms,nvr,configs,screenshots}` on
   first run, so `rm -rf` the target immediately before symlinking).

4. **`--config file.cfg` is honoured** (sets `config_file_default`, loaded via
   `config_load(CFG_MACHINE, ...)` inside `start_emulation()`, called
   automatically at startup — no GUI interaction needed as long as
   `config_override` gets set, which happens automatically when `--config` is
   passed). PCem **auto-saves the config file on exit** (including on a plain
   `pkill` without `-9`), so a graceful kill can silently overwrite your hand
   edits with whatever was in memory. Use `pkill -9 -x pcem` while iterating.
   (`pkill -f './pcem'` will also match — and kill — the *invoking shell*
   itself if the shell's own command-line string contains the substring
   `./pcem`; use `-x pcem` for an exact-name match instead.)

5. **The hard-disk config key names don't follow the a/b/c/d IDE-letter
   convention you'd expect.** From `pc.c`, `ide_fn[7]` (the drive slots) map to
   config keys as: **`hdc_fn` → index 0 (Primary Master)**, `hdd_fn` → index 1
   (Primary Slave), `hde_fn` → index 2, `hdf_fn` → index 3, etc. — i.e. the
   *first* drive is configured via `hdc_*`, not `hda_*`/`hdd_*` as the naming
   suggests. Get this wrong and Primary Master silently stays empty.

6. **The disk image needs to be on a writable mount.** `hdd_file.c`'s
   `hdd_load_ext()` opens non-read-only drives with `fopen64(fn, "rb+")` — a
   `:ro` bind-mount makes this fail silently (`hdd->f == NULL` → `IDE_NONE`),
   with **no error logged** (release builds compile out `pclog` entirely via
   `#ifndef RELEASE_BUILD`). Copy the disk image to a writable path first.

7. **Unresolved**: even with a writable raw disk image (valid MBR, confirmed
   `55 AA` boot signature) on a writable mount, at the correct config key
   (`hdc_fn`), at the *exact* file size implied by the configured CHS
   (1024×16×63×512 = 528,482,304 bytes, byte-for-byte) — the BIOS still
   reports **"Primary master hard disk fail"** at boot. Confirmed via direct
   source reading that the config→geometry threading is correct end-to-end
   (`pc.c` → `hdc[0].spt/hpc/tracks` → `hdd_load_ext()` → `hdd->spt/hpc/tracks`
   all match; `ide_identify()`'s reported geometry matches what
   `ide_get_sector()` uses for CHS→LBA translation). Whether this is a
   raw-vs-VHD handling bug in this build's `minivhd` integration, or a
   PIIX-IDE-channel-enable timing issue (`piix.c`'s `card_piix_ide[0x41]`/`[0x43]`
   bit-0x80 gating of `ide_pri_enable()`) specific to this BIOS ROM's
   expectations, wasn't isolated further — see "Next steps" below.

8. **BIOS Setup keyboard input requires the SDL window's mouse to be
   *captured* first** (see TL;DR above). Without it, keys are silently
   dropped/delayed at unpredictable rates — this looks exactly like "the
   emulator is buggy/hanging" but is actually an input-delivery problem.
   Fix, once per fresh container/process:
   ```sh
   docker exec <container> bash -c "export DISPLAY=:99; xdotool windowfocus <winid>; xdotool mousemove --window <winid> <cx> <cy>; xdotool click 1"
   ```
   Find `<winid>` via `xdotool search --name pcem` or by geometry
   (`xdotool getwindowgeometry`); the PCem SDL window's title changes to
   "Press CTRL-END or middle button to release mouse" once captured. After
   that, drive the emulator's `sendKey()`/`sendPointer()` over VNC as usual —
   just make sure to wait for the *actual* `connect` event (poll
   `fb.connected`) rather than a blind `setTimeout`, since `sendKey()` silently
   no-ops (`return false`) if called before the RFB handshake completes.

## Scripts

### `build-pcem.sh`
Builds PCem v17 from source into `/work/pcem` (~5 min, far faster than the
qemu-3dfx build — no QEMU source tree involved).
```sh
docker run -d --name pcem-build -v <BUILD_DIR>:/work debian:bookworm-slim sleep infinity
docker exec -d pcem-build bash -c "bash /work/build.sh > /work/build.log 2>&1"
# wait for BUILD_OK
```

### `run-pcem-headless.sh`
Xvfb :99 → x11vnc bridges to VNC :5901 → launches `./pcem --config pcem.cfg`.
Requires `roms/` (with the BIOS dumps described above) and a writable
`disk.img` alongside it; see `pcem.cfg.example` for the exact keys.
```sh
docker exec -d pcem-run bash /work/run.sh
```

### `pcem.cfg.example`
A working `430vx` + `v3_3000` config — **as far as it got** (BIOS POSTs,
Voodoo3 detected, hard disk not yet functional; see gotcha #7). Update
`hdc_fn` to your actual writable disk path before use.

## Next steps if resuming this
- Try a genuinely VHD-formatted disk image (this build's `minivhd` integration
  may only be reliable for VHD, not raw `.img`, despite `hdd_load_ext()`
  nominally supporting both) — the one config-shaped variable *not* yet ruled
  out.
- Try a different IDE-capable machine model with its own bundled/sourceable ROM
  (e.g. a Slot-1 board like `ga686bx`) to isolate whether the bug is specific
  to the 430VX+PIIX combination or general to PCem's IDE emulation.
- Consider **86Box** instead (the actively-maintained PCem-lineage project;
  prebuilt Linux AppImage + ROM set already downloaded during this session at
  the same source used for the BIOS-dump cross-reference above) — the original
  evaluation doc
  ([`docs/knowledge/emulation/pcem-86box-runtime-evaluation.md`](../../../docs/knowledge/emulation/pcem-86box-runtime-evaluation.md))
  already recommended 86Box over PCem for exactly this kind of maintenance gap,
  and it may simply have this IDE bug fixed already given its active
  development. Needs the user to confirm running the downloaded AppImage
  (external binary execution).
