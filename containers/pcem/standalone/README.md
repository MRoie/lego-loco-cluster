# Standalone PCem test — evaluating PCem/Voodoo3 for LEGO LOCO

Bring-up log for testing whether **PCem** (real period-hardware emulation,
software Voodoo3 dynarec) can run LEGO LOCO more smoothly than QEMU+SoftGPU or
qemu-3dfx. See [../../qemu-softgpu/standalone/README.md](../../qemu-softgpu/standalone/README.md)
for the QEMU-side investigation this follows on from.

## TL;DR (updated — second session)
- **"Primary master hard disk fail" (gotcha #7 below) is a `RELEASE_BUILD`
  compiler-optimization bug, not a config or geometry issue.** Rebuilding PCem
  in **debug mode** (`./configure --enable-debug`, **`make clean` first** — see
  gotcha #9) makes the exact same config/disk detect correctly every time. This
  is the single most important finding: it unblocks disk use entirely at the
  BIOS-detection level, on **any** machine model.
- With detection fixed, moved to the `fic_va503p` (VIA MVP3 / Socket 7) model
  per a deliberate model-swap test, sourced its BIOS the same way (86Box ROM
  set), got a fresh disk partitioned via FDISK and formatted — and hit a
  **second, distinct bug**: any *guest-side, multi-sector* disk read (`dir c:`,
  `format c:`, even just switching the current drive to `c:`) hangs the
  emulator completely (100%+ CPU busy-spin, unresponsive to all keys including
  Escape). Single-sector I/O (BIOS's own MBR read, FDISK's MBR write) always
  works fine — it's specifically multi-sector transfers that hang.
- Ruled out the classic "528 MB / 1024-cylinder CHS barrier" as the cause: built
  a second disk at 1023 cylinders (503 MB, just under the barrier) — identical
  hang. Ruled out `fic_va503p`/VIA-MVP3-specific IDE emulation as the cause too:
  switched to `430vx` (Intel i430VX/PIIX) with the **same debug build** and the
  **same disk** — BIOS detection works (`Detecting IDE Primary Master ...
  PCemHD`), but the identical hang reproduces the moment DOS touches partition
  *contents*. Two unrelated chipsets, same symptom → **this points to a bug in
  PCem's shared/generic IDE PIO-transfer code, not any one chipset's emulation**
  (see gotcha #10). Not yet isolated to a specific line; a next step if picked
  back up is bisecting against an older PCem release to see if this is a
  regression or has always been present (`pcem-old` is untested as of this
  writing).
- **Workaround found for partitioning/formatting without ever touching the
  buggy guest-side path**: write the MBR partition table entry directly (16
  bytes at offset 446, byte layout is completely standard/self-describing —
  see gotcha #11) and format the partition with **`mtools`** (`mformat`, via a
  `.mtoolsrc` `offset=`/`cylinders=`/`heads=`/`sectors=` drive definition)
  directly against the disk image file from the host/build container — no PCem
  process involved at all for this step. This produces a byte-valid,
  guest-readable FAT16 filesystem; the only thing that still doesn't work is
  the guest *itself* reading it back once booted.
- Confirmed PCem's disk **write-back cache is only flushed to the host file on
  a clean process exit** — `pkill` (even plain `SIGTERM`, even a `SIGINT`) is
  silently ignored by this build and leaves all FDISK/format writes trapped in
  memory; only `SIGKILL` actually terminates the process, and that always
  discards the cache. The only clean-exit path found is sending a real
  `WM_DELETE_WINDOW` to the wx top-level frame (`xdotool windowclose
  <wx-frame-winid>`, **not** the SDL child window), which does trigger
  `Frame::OnClose` → `wx_exit()` — but even that left the emulation thread
  running headless in this build (see gotcha #12), so the safest known-working
  pattern for any test that needs the write to land on disk is: **do the
  disk-mutating step directly via `mtools`/a byte-level script on the host
  file, never through the live guest.**
- Windows 98 has still never actually booted under PCem — blocked on the
  generic IDE multi-sector-read hang above.

### First-session TL;DR (kept for history)
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
  **Update: this was the `RELEASE_BUILD` compiler bug — see the second-session
  TL;DR above.**

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

9. **Changing `./configure` flags does NOT force a rebuild — `make clean` is
   required first.** Reconfiguring from `--enable-release-build` to
   `--enable-debug` (or vice versa) and running `make` alone silently reuses
   every stale `.o` file compiled with the *old* flags (`cp pcem ..` /
   "Nothing to be done" — a near-instant no-op build that looks successful).
   Confirmed by counting `gcc`/`g++` invocations in the build log: 0 on the
   no-op vs. 318 on a real rebuild after `make clean`. **This is the fix for
   gotcha #7's "Primary master hard disk fail"**: the release build
   (`-O2/-O3 -DRELEASE_BUILD`) has a reproducible, compiler-optimization-
   sensitive bug (almost certainly UB/an uninitialized value) somewhere in the
   disk-detection path that a plain `-O0 -g -D_DEBUG` debug build does not
   trigger — same `pcem.cfg`, same disk file, only the build flags differ.
   `pclog()` (writes to `~/.pcem/pcem.log`, no `fflush()` in the source, so it
   rarely reaches disk before a clean exit) was a dead end for finding the
   *specific* line, but forcing a full debug rebuild to test it is what
   incidentally fixed the bug.

10. **A second, distinct bug survives the debug-build fix**: once the BIOS
    correctly detects the disk, any *guest-side* multi-sector read of
    partition contents — `dir c:`, `format c:`, even just typing `c:` to
    switch the current drive — hangs the emulator solid (sustained 100%+ CPU,
    unresponsive to every key including Escape; confirmed via cursor-blink
    diffing between screenshots taken seconds apart — zero byte difference).
    Single-sector operations (BIOS's own MBR probe at boot, FDISK's MBR
    write) always succeed. Ruled out as the cause:
    - **The classic 528 MB/1024-cylinder CHS barrier** — built a second disk
      at 1023 cylinders (503 MB, just under the barrier) with a from-scratch
      MBR; identical hang.
    - **The `fic_va503p` (VIA MVP3) chipset specifically** — switched to
      `430vx` (Intel i430VX/PIIX) with the *same* debug binary and the *same*
      disk image; BIOS detection succeeds (`Detecting IDE Primary Master ...
      PCemHD`) but the hang reproduces identically the moment DOS reads
      partition contents.

    Two chipsets from different PCem machine-model source files, same
    symptom → the bug most likely lives in **shared IDE PIO-transfer code**
    (multi-sector `READ SECTORS`/interrupt-completion handling), not
    chipset-specific southbridge emulation. Not yet isolated to a specific
    function/line. **Untested next step**: try an older tagged PCem release
    (pre-v17) with the same debug-build recipe, to check whether this is a
    regression or has always been present — would help decide whether
    bisecting PCem's own history is worthwhile versus moving to 86Box.

11. **Partitioning/formatting can be done entirely from the host, bypassing
    the guest (and gotcha #10's hang) completely.** The MBR partition-table
    entry is a fixed, fully-documented 16-byte structure at file offset 446:
    `[boot 0x80][CHS start 3B][type 1B][CHS end 3B][LBA start u32LE][sector
    count u32LE]`, followed by the `55 AA` signature at offset 510. For a
    disk with `heads=16 sectors=63`, standard alignment starts the first
    partition at LBA 63 (head 1, sector 1, cylinder 0); CHS end and total
    sectors follow directly from the configured cylinder count. A ~30-line
    Node script (`Buffer` + `fs.writeSync` at explicit offsets) reproduces
    byte-for-byte what FDISK itself writes — confirmed by diffing against a
    real FDISK-written MBR read back with `od`. Once the MBR is in place,
    `mtools`' `mformat` can create the FAT16 filesystem directly on the
    partition via a `.mtoolsrc` drive definition:
    ```
    drive c: file="/path/to/disk.vhd" offset=32256 cylinders=1023 heads=16 sectors=63 mformat_only
    ```
    (`offset` is `LBA_start * 512` in bytes; `mformat_only` skips mtools'
    own partition-table sanity dance since we already wrote a valid one).
    `minfo`/`mdir` against the same drive definition confirm a valid,
    guest-readable FAT16 volume with the expected free space — entirely
    without launching PCem. `mtools` isn't preinstalled in the runtime
    container; `apt-get install -y mtools` (Debian bookworm base) is instant.

12. **PCem's disk write-back cache only reaches the host file on a clean
    process exit — and this build resists every standard way of asking for
    one.** `pkill -x pcem-debug` (plain `SIGTERM`) and `kill -INT` are both
    silently ignored (process keeps running, unchanged CPU%, for over 10s of
    observation). Only `SIGKILL` (`pkill -9`) actually terminates it, and that
    always discards whatever FDISK/format writes hadn't been flushed yet —
    confirmed by reading the MBR bytes back with `od` immediately after a
    `-9` kill and finding them still all-zero despite FDISK having reported
    "Primary DOS Partition created" moments earlier. The one thing that does
    get PCem's own close handler to run is sending a real `WM_DELETE_WINDOW`
    to the **wx top-level frame** (a separate, tiny ~10×10 window titled
    `pcem-debug` — *not* the visible SDL render window titled `PCem v17 - ...`)
    via `xdotool windowclose <wx-frame-winid>`; wxWidgets' source
    (`wx-app.cc`) confirms this fires `Frame::OnClose` → `wx_exit()`. In
    practice this still left the emulation thread running headless
    afterwards in this build, so it wasn't a fully reliable clean-shutdown
    path either — the practical workaround that *was* reliable is gotcha #11
    (do the write from the host, skip needing PCem to flush anything at all).

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
- **Try an older PCem release** (pre-v17, e.g. v16 or v15) with the same
  debug-build recipe (gotcha #9) against the same mtools-formatted disk
  (gotcha #11), to check whether the generic multi-sector IDE hang (gotcha
  #10) is a regression introduced at some point in PCem's history or has
  always been present. If an older version doesn't hang, bisecting between
  that version and v17 would isolate the actual commit/bug far faster than
  reading `ide.c` cold.
- If bisection isn't fruitful, read PCem's shared IDE controller source
  (`ide.c`, focus on multi-sector `READ SECTORS`/`WRITE SECTORS` command
  handling and IRQ-completion signalling) directly for the bug — both tested
  chipsets (`fic_va503p`, `430vx`) route through the same generic IDE code, so
  the bug should be visible there rather than in per-chipset southbridge files.
- Consider **86Box** instead (the actively-maintained PCem-lineage project;
  prebuilt Linux AppImage + ROM set already downloaded during this session at
  the same source used for the BIOS-dump cross-reference above) — the original
  evaluation doc
  ([`docs/knowledge/emulation/pcem-86box-runtime-evaluation.md`](../../../docs/knowledge/emulation/pcem-86box-runtime-evaluation.md))
  already recommended 86Box over PCem for exactly this kind of maintenance gap,
  and it may simply have this IDE bug fixed already given its active
  development. Needs the user to confirm running the downloaded AppImage
  (external binary execution).
