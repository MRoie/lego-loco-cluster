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
- **Blocked**: the emulated hard disk consistently fails ("Primary master hard
  disk fail" at boot; BIOS's own "IDE HDD AUTO DETECTION" utility hangs/loops
  indefinitely across all 4 IDE slots). Root cause not resolved — see below.
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
   (`hdc_fn`) — the BIOS still reports **"Primary master hard disk fail"**
   at boot, consistently, across multiple CHS geometries tried (16/63/1024
   classic-CHS, 255/63/261 LBA-style). The BIOS's own "IDE HDD AUTO DETECTION"
   SETUP utility does eventually detect *something* (device responds to
   IDENTIFY, since POST shows `PCemHD` as the drive's self-reported name) but
   the auto-detect **loops indefinitely** re-probing all 4 IDE slots rather
   than terminating with a result — never seen to complete. Whether this is a
   raw-vs-VHD disk-image handling bug in this build's `minivhd` integration, an
   IDE/BIOS timing issue, or something specific to the `430vx` + `v3_3000`
   combination wasn't isolated further in this session.

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
  nominally supporting both).
- Try a different/simpler machine model (e.g. an ISA-only 486 board) to
  isolate whether the bug is IDE/PCI-specific or general.
- Consider **86Box** instead (the actively-maintained PCem-lineage project;
  prebuilt Linux AppImage available, ROM set already downloaded during this
  session at the same source used for the BIOS-dump cross-reference above) —
  the original evaluation doc
  ([`docs/knowledge/emulation/pcem-86box-runtime-evaluation.md`](../../../docs/knowledge/emulation/pcem-86box-runtime-evaluation.md))
  already recommended 86Box over PCem for exactly this kind of maintenance gap.
