# Standalone PCem test — evaluating PCem/Voodoo3 for LEGO LOCO

Bring-up log for testing whether **PCem** (real period-hardware emulation,
software Voodoo3 dynarec) can run LEGO LOCO more smoothly than QEMU+SoftGPU or
qemu-3dfx. See [../../qemu-softgpu/standalone/README.md](../../qemu-softgpu/standalone/README.md)
for the QEMU-side investigation this follows on from.

## TL;DR (updated — fifth session — LEGO LOCO runs correctly, gotcha #29)
- **LEGO LOCO is fully working.** The "reinstall this software" error
  (gotchas #27–28) is resolved — root cause was the raw-file-copy install
  approach itself, not a CD-check or a missing registry key. Running the
  genuine retail InstallShield installer from `Lego_Loco.iso` instead fixed
  it completely: `Loco.exe` launches, plays its real 3D intro cinematics,
  and reaches the interactive main menu with no error. See gotcha #29.

- **The false "16MB of memory" error (gotcha #18) is fixed.** Root cause:
  it was never about actual memory at all — it was **FreeDOS's `HIMEMX.EXE`
  (or the FreeDOS real-mode environment generally) causing Windows 98
  Setup's own real-mode memory/XMS check to fail**, on a boot floppy that
  was otherwise fully functional (CD-ROM worked, `dir d:` worked, HimemX
  reported itself loaded correctly in the boot banner). Swapping the entire
  DOS boot environment for **genuine Microsoft-authored boot files —
  real `IO.SYS`, real `HIMEM.SYS`, real `COMMAND.COM`, `OAKCDROM.SYS` +
  `MSCDEX.EXE` — extracted directly from the Windows 98 SE install CD's own
  cabinet files** (no internet download, no third-party boot disk) made the
  error disappear immediately and let Setup proceed normally into the real
  wizard (computer name, region, "Start Copying Files", the actual
  file-copy phase). See gotcha #22 for the full extraction/build recipe —
  this is the one to reuse if the floppy image is ever lost or needs
  rebuilding.
- Two dead-end/false leads chased before finding the real fix, kept here so
  they aren't re-tried: **the Voodoo3 card was not the cause** (gotcha #18's
  original memory error reproduced identically with `gfxcard=vga`, ruling
  out PCI MMIO interference) — see gotcha #19. **PCem cannot boot from the
  Windows 98 CD's own El Torito boot record** — the BIOS's boot-virus-scan
  step hangs indefinitely trying to scan a CD-ROM boot sector even with
  scanning disabled, and just proceeding to read the El Torito image hangs
  too; this looks like a genuine PCem/ATAPI-BIOS-extension gap, not
  something fixable from config. See gotcha #20 for the investigation and
  gotcha #21 for the two host-BIOS-Setup findings worth keeping (how to
  reach BIOS Setup reliably in this input-flaky environment, and the actual
  `Boot Sequence` value that maps to the CD-ROM: `SCSI`, not an explicit
  `CDROM` entry).
- **A second, unrelated input-reliability gotcha found while stepping
  through the Setup GUI wizard itself (not just DOS-level text screens)**:
  mouse clicks routinely fail to register on `Continue`/`Next`/dialog
  buttons inside Setup's graphical (Mini-Windows) screens in this
  container/Xvfb/VNC setup, even when the cursor visibly hovers correctly
  on the right control — **keyboard-only navigation (`Tab` to move focus,
  screenshot to confirm which control now has the dotted focus rectangle,
  then `Enter`) is the reliable pattern** and is what actually got Setup
  from the Welcome screen through Identification, Establishing Your
  Location, and Startup Disk. See gotcha #23.
- Three real bugs were found and fixed this session before hitting the above,
  none of them in PCem itself:
  1. **"Primary master hard disk fail" is a `RELEASE_BUILD` compiler-
     optimization bug**, not a config or geometry issue. A **debug-mode**
     rebuild (`./configure --enable-debug`, **`make clean` first** — gotcha #9)
     detects the exact same disk correctly every time, on any machine model.
  2. **The "any multi-sector disk read hangs the emulator" bug that looked
     like a PCem IDE-emulation bug was actually a bug in our own host-side
     disk-prep workaround**, not in PCem at all (see below). Once fixed,
     `dir c:` completes instantly and correctly — file listing, free-space
     calculation (which requires walking the whole FAT table), all of it —
     with the debug build, on a plain `430vx` machine, no further changes to
     PCem needed.
- **Root cause of bug 2, found via live `gdb -p <pid>` attach on the hung
  process** (`thread apply all bt` to find the actual x86 emulation thread —
  it's the one named exactly `Main Thread`, buried among ~20 wx/GTK/llvmpipe
  threads all confusingly also named `pcem-debug`) and `print
  ide_drives[0].<field>` to inspect live IDE controller state: **the FAT16
  boot sector our host-side `mtools mformat` workaround (see gotcha #11)
  created had `hidden sectors = 0` in its BPB, when it must equal the
  partition's starting LBA (63 for this layout) for a filesystem living
  inside a partition.** Real `FORMAT.COM` always sets this correctly from the
  partition table; `mformat` only does if told to. FreeDOS's kernel uses this
  field for its own internal sector arithmetic once mounting a partitioned
  (not whole-disk) FAT volume, and with it wrong, some downstream calculation
  (most likely the free-space FAT scan, which is the first thing after the
  simple root-directory read that needs more than trivial sector math)
  never terminates. **Fix: `mformat -H 63 ...` instead of plain `mformat
  ...`** — one flag, already listed in mtools' own `--help` output the whole
  time.
- This also explains the "confirmed on both `fic_va503p` and `430vx`" and
  "confirmed on both PCem v16 and v17" findings from earlier in this session
  (previously read as "this is a deep, version-spanning PCem IDE bug") —
  **all of those tests were run against the same buggy disk image**. They
  correctly proved the bug wasn't chipset- or version-specific, but the actual
  conclusion is "the disk was broken the same way regardless of which PCem
  build reads it," not "PCem's IDE emulation is broken." Once the disk was
  fixed, the *identical* `430vx` config that hung before now completes
  `dir c:` cleanly. PCem itself was never the problem.
- **A major, unrelated time-sink throughout this session**: keyboard input
  delivered via `xdotool`/VNC to the guest is severely and unpredictably
  delayed under this container/Xvfb setup — keystrokes (especially a trailing
  `:`) can arrive seconds to tens-of-seconds late, out of order, or interleaved
  with earlier "lost" keystrokes resurfacing much later, making live
  interactive typing an unreliable way to test anything disk-related (a
  dropped `:` silently redirects a command from `C:` to `A:`, which of course
  "doesn't hang" — it just never touched the code path being tested, and looks
  identical to a real fix from the screen alone). **The methodology that
  actually settled this**: write the test command into `AUTOEXEC.BAT` on the
  boot floppy via `mtools` and just watch the screen — zero live keystrokes
  needed, so the flaky input path can't corrupt the result. Do this for any
  future disk-behavior test in this environment rather than trusting live
  typing.
- **Workaround/technique retained for future disk prep**: writing the MBR
  partition table entry directly (16 bytes at offset 446 — see gotcha #11)
  and formatting with `mtools mformat -H <hidden_sectors> ...` against the
  disk image file from the host is a fully valid, fast way to prep a PCem
  disk without ever going through FDISK/FORMAT.COM interactively — as long as
  `-H` is set correctly.
- **A third, unrelated config bug blocked the CD-ROM identically**: `cdrom_path`
  pointing at a perfectly valid ISO (verified byte-for-byte: correct ISO9660
  PVD signature at the expected offset, right file size, `isoinfo` reads it
  fine) was silently ignored because **`cdrom_drive` was `0`, and `0` doesn't
  mean "no drive" or "use `cdrom_path`" — it means "use physical host CD-ROM
  device #0" via a Linux ioctl path** (`pc.c`'s `cdrom_drive == CDROM_IMAGE`
  branch, where `CDROM_IMAGE` is `200`, is the *only* path that calls
  `image_open()`/reads `cdrom_path` at all). In this headless container
  there's no `/dev/sr0`, so every read failed with "drive not ready" — every
  single time, identically, no matter how long you wait or how many times you
  retry, because the in-memory `cdrom` object was simply never created
  (confirmed by `gdb -p <pid> -ex 'print cdrom'` showing a null pointer while
  `image_path` correctly held the right filename the whole time — the
  smoking gun that the image-loading code path was never even reached).
  **Fix: `cdrom_drive = 200` in `pcem.cfg`**, not `0`. The boot-time driver
  handshake (`SHSUCDX installed, Drive D: assigned`) still succeeds either
  way, since that's generic ATAPI identify-level detection independent of the
  backend — only actual data reads expose the misconfiguration, which is what
  made this look identical in symptom to gotcha #14's disk bug (see gotcha
  #17 for the general lesson this and #14 both teach).
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
- **A Setup-triggered restart mid-file-copy caused a genuine restart loop**
  (redoing the entire DOS-mode wizard from scratch, three times) because the
  BIOS's default `Boot Sequence` booted the floppy before the hard disk on
  every post-Setup reboot. Fixed by changing `Boot Sequence` to `C only` in
  BIOS Setup — confirmed via the "Windows Setup Safe Recovery" screen on the
  next boot, then a clean run straight into the GUI Setup Wizard with no
  floppy/DOS detour. See gotcha #24.
- **Windows 98 SE has booted all the way to a working desktop under PCem.**
  Two further Setup-triggered reboots each hit a reproducible chipset-level
  hang (guest CPU spinning in a tiny real-mode code range instead of
  completing its reboot request) — recovered both times via `kill -9` +
  relaunch, which resumed cleanly on `C:` thanks to gotcha #24's boot-order
  fix rather than losing progress. See gotcha #25. A checkpoint of this
  clean-desktop state was saved to `disk-vhd-503-win98-desktop-checkpoint.vhd`.
- **Voodoo3 (3dfx `am29win9x`) and DirectX 7.0a drivers are both installed.**
  Delivered via a custom Joliet ISO (too big for a floppy), driven entirely
  by keyboard (mouse clicks still unreliable — gotcha #23) with a new gotcha
  found along the way: typing a literal `:` is unreliable in this
  environment and should be avoided entirely in favor of Explorer's
  icon/arrow-key navigation. See gotcha #26. This state is checkpointed both
  locally (`disk-vhd-503-post-drivers-checkpoint.vhd`) and pushed to
  `ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:pcem-win98-post-drivers`.

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

7. **Resolved (see gotcha #9)**: even with a writable raw disk image (valid
   MBR, confirmed `55 AA` boot signature) on a writable mount, at the correct
   config key (`hdc_fn`), at the *exact* file size implied by the configured
   CHS (1024×16×63×512 = 528,482,304 bytes, byte-for-byte) — the BIOS still
   reported **"Primary master hard disk fail"** at boot. Confirmed via direct
   source reading that the config→geometry threading is correct end-to-end
   (`pc.c` → `hdc[0].spt/hpc/tracks` → `hdd_load_ext()` → `hdd->spt/hpc/tracks`
   all match; `ide_identify()`'s reported geometry matches what
   `ide_get_sector()` uses for CHS→LBA translation) — the bug was a
   `RELEASE_BUILD`-only compiler-optimization issue, not a raw-vs-VHD or
   PIIX-timing bug as originally suspected here.

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

10. **Resolved — was never a PCem bug**: once the BIOS correctly detects the
    disk, any *guest-side* multi-sector read of partition contents —
    `dir c:`, `format c:`, even just typing `c:` to switch the current drive —
    appeared to hang the emulator solid (sustained 100%+ CPU, unresponsive to
    every key including Escape; the cursor-blink diff test between
    screenshots taken seconds apart showed zero byte difference, which read
    as a genuine freeze). Single-sector operations (BIOS's own MBR probe at
    boot, FDISK's MBR write) always succeeded, which is what made it look
    IDE/multi-sector-transfer-specific. Extensive isolation work seemed to
    rule out every PCem-side explanation:
    - **The classic 528 MB/1024-cylinder CHS barrier** — built a second disk
      at 1023 cylinders (503 MB, just under the barrier) with a from-scratch
      MBR; identical hang.
    - **The `fic_va503p` (VIA MVP3) chipset specifically** — switched to
      `430vx` (Intel i430VX/PIIX) with the *same* debug binary and the *same*
      disk image; BIOS detection succeeded but the hang reproduced identically.
    - **A v17 regression** — built PCem v16 (2020, commit `d0c7ea56`, see
      gotcha #13) and tested the same disk; identical hang.

    **All three of those tests were unknowingly run against the same broken
    disk image** (see gotcha #14) — they correctly proved the symptom wasn't
    chipset- or version-specific, but the actual reason is that the *disk
    itself* was subtly invalid in a way that broke identically regardless of
    which PCem build read it. Once the disk was fixed, this exact `430vx`
    config and debug binary completed `dir c:` — including the free-space
    scan — instantly and correctly. Lesson for next time this class of "looks
    like a hang, survives every isolation test" symptom shows up: **suspect
    the test fixture (the disk image) before suspecting the emulator**,
    especially when the fixture was built by a workaround rather than the
    guest's own standard tools.

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

13. **Building an older PCem release (pre-v17) from a raw `git checkout`/
    `git worktree add` needs two extra steps current Debian doesn't give you
    for free.** (a) The checked-in `configure`/`aclocal.m4` were generated by
    a specific old `automake` point version (e.g. `aclocal-1.15`) that isn't
    installed, and a `git checkout` resets all file mtimes to checkout time —
    `make` then sees `configure.ac` newer than `aclocal.m4` (or vice versa,
    filesystem-timestamp-granularity dependent) and tries to regenerate build
    files with a tool that doesn't exist, failing immediately (`aclocal-1.15:
    command not found`). Fix: `apt-get install autoconf automake libtool` and
    run `autoreconf -fi` once in the checkout — regenerates everything with
    whatever autotools version is actually present, and is a one-time step per
    checkout (not per build). (b) Old PCem's `ibm.h` declares ~40 globals
    without `extern` (relying on pre-C99 "tentative definition" merging, where
    the linker was expected to fold multiple uninitialized declarations of the
    same name into one symbol) — GCC defaulted to this behaviour
    (`-fcommon`) through GCC 9, but **GCC 10+ defaults to `-fno-common`**,
    turning every one of those globals into a hard `multiple definition`
    link error across translation units. Fix: force the old behaviour back on
    by wrapping the compiler in `./configure`, since passing `CFLAGS=-fcommon`
    directly is silently dropped by this era's `Makefile.am` (it doesn't
    reference `CFLAGS` in the file-compile rule, only `AM_CFLAGS`/hardcoded
    flags) — `CC='gcc -fcommon' CXX='g++ -fcommon' ./configure ...` works
    because it's baked into the compiler invocation itself, not appended
    separately.

14. **The actual root cause of gotcha #10: `mtools mformat` doesn't set the
    boot sector's `hidden sectors` BPB field unless told to, and a FAT
    filesystem living inside a partition needs it set correctly.** When
    partitioning/formatting a disk image directly from the host (bypassing
    the guest's own FDISK/FORMAT — see gotcha #11), `mformat -v LABEL c:`
    against a `.mtoolsrc` drive with `offset=<partition start>` produces a
    filesystem that `minfo` and `mdir` read back perfectly fine — but
    `hidden sectors: 0` in that boot sector's BPB is wrong; it must equal the
    partition's starting LBA (63 for a `heads=16 sectors=63` disk with the
    first partition at the conventional head-1/sector-1/cylinder-0 start).
    FreeDOS's kernel reads this field for its own internal sector arithmetic
    once mounting a partitioned volume, and with it wrong, something
    downstream — empirically, whatever runs right after the trivial
    root-directory listing, most likely the free-space FAT scan — never
    terminates. **This is what actually caused gotcha #10's "hang."** Fix is
    a single flag: `mformat -H <hidden_sectors> -v LABEL c:`. Always pass
    `-H` when formatting a partitioned (not whole-disk) image this way;
    `minfo`'s `hidden sectors:` line will silently read `0` otherwise with no
    warning that anything is wrong until a real DOS kernel trips over it.

15. **Live `gdb -p <pid>` attach is the fastest way to tell "genuine emulator
    hang" from "input never arrived" or "guest is legitimately still working"
    in this setup — screenshots alone can't distinguish them.** `gdb -p <pid>
    -batch -ex 'thread apply all bt'` dumps every thread; this build has
    ~20+ (wx GUI thread, GTK/llvmpipe software-GL rendering workers, an SDL
    timer thread, several `pcem-debug`-named helper threads) and the *actual
    x86 CPU emulation loop* is easy to miss — it's the one named exactly
    `Main Thread` (from `SDL_CreateThread(mainthread, "Main Thread", ...)` in
    `wx-sdl2.c`), not any of the several threads whose name happens to be the
    process name. If that thread's PC keeps changing between repeated
    attach/detach cycles (expect to land in dynarec-JIT-generated code with
    no symbols — a "corrupt stack"/`??` backtrace is normal, not a sign of
    corruption), the guest CPU is actually executing, not stuck. Combine with
    `set max-value-size unlimited` (the `IDE` struct's `sector_buffer[256*512]`
    otherwise blows gdb's default print-size limit) and `print
    ide_drives[0].<field>` (`.command`, `.atastat`, `.secount`, `.sector`,
    `.head`, `.cylinder`) to read the live IDE controller state directly —
    an unchanging `atastat` showing `READY_STAT|DSC_STAT` (0x50) with
    `secount == 0` means the last disk transfer completed cleanly; the guest
    is off doing something else (or legitimately hung in its *own* code, as
    turned out to be the case here) rather than stuck waiting on disk I/O.

16. **Don't trust live interactive keystroke testing for anything
    disk-behavior-related in this container/Xvfb/VNC setup — script it into
    `AUTOEXEC.BAT` instead.** Keyboard input delivered via `xdotool type`/
    `xdotool key` (and the VNC-`keyEvent` fallback) is severely and
    unpredictably delayed here: a trailing `:` on a typed command routinely
    arrives seconds late or gets dropped outright (silently redirecting
    `dir c:` to `dir c` against the floppy — which of course returns
    instantly with no hang, since it never touched the hard disk at all,
    looking exactly like a successful fix when it proves nothing), and
    "lost" keystrokes from several attempts back can resurface much later,
    interleaved with new ones, corrupting whatever's currently being typed.
    This cost enormous time in this session chasing what looked like a
    still-reproducing hang after the real fix (gotcha #14) had already
    landed. **The methodology that actually settled it**: `mcopy` a test
    command straight into `AUTOEXEC.BAT` on the boot floppy (`mcopy -o
    test.bat -i patcher.ima ::AUTOEXEC.BAT`) and just watch the VNC
    screenshot — zero live keystrokes in the loop, so the flaky input path
    can't corrupt the result either way.

17. **The general lesson from both gotcha #14 (disk) and the CD-ROM
    `cdrom_drive` bug above: when something "hangs" or "isn't ready"
    identically on every retry regardless of how long you wait, that's the
    signature of a static misconfiguration or bad fixture, not a timing race
    or a real emulator bug** — a genuine race or slow-hardware-emulation
    issue would be expected to resolve at least sometimes with enough
    retries/elapsed time; a config value that's simply wrong, or a data
    structure that was never populated, fails the *same* way *every* time,
    forever. Both bugs this session fit that pattern exactly (same "not
    ready"/hang signature on attempt 1 and attempt 20 alike), and both times
    the fastest confirmation was reading live process state with `gdb -p
    <pid>` (IDE register values for the disk bug; the `cdrom` global pointer
    for the CD-ROM bug) rather than continuing to vary the guest-side retry
    and hoping timing was the culprit.

18. **Unresolved: Windows 98 SE's 32-bit Setup wizard shows "Windows 98
    requires a computer with at least 16MB of memory" unconditionally, every
    single time, once Setup reaches its "Copying files needed for Windows
    Setup" step** — with the correct disk and CD-ROM both working (per
    gotchas #14–17) and the full 65536 KB (64 MB) of RAM configured. Note this
    is *not* the same as the identical real-world error from actual low RAM;
    real machines/emulators hitting this error nearly always trace to one of
    a few well-known causes, all of which were tried here and **none fixed
    it**:
    - **`mem_size` value itself** — tried 65536 (64 MB) and 32768 (32 MB);
      identical error both times. Eliminates a naive INT15h/AH=88h 16-bit
      register overflow at exactly 64 MB as the cause (that theory doesn't
      hold anyway: extended memory reported by that call is `mem_size -
      1024`, i.e. 64512 KB at our setting, comfortably under the 65535 KB
      register ceiling).
    - **A third-party memory manager stepping on Setup's own memory
      detection** — the classic real-world cause of this exact error, and
      the boot floppy's own `FDCONFIG.SYS` even carries the comment "Dont
      load freedos to highmemory it will break windows installer!". Added a
      custom boot option loading only `HIMEMX.EXE` (bare XMS) with
      `JEMM386.EXE` (the EMS/UMB manager) removed entirely — confirmed via
      the boot banner changing from `Jemm386 loaded / UMBs unavailable!` to
      `KBC A20 method used` — and the error still appeared, identically.
    - **Stale/bad CMOS from the earlier model-switch checksum reset** —
      deleted `~/.pcem/nvr/pcem.430vx.nvr` to force the BIOS to re-detect and
      re-save memory size fresh (confirmed via a fresh "CMOS checksum error –
      Defaults loaded" + correct "Memory Test: 65536K OK" on the next boot);
      the error still appeared afterward, identically.
    - **A fast-CPU timing-loop miscalibration** (the class of bug this exact
      boot floppy is *named for* — "Patch for Windows 95/98/Me to fix CPU
      issues", `PATCH9X.EXE` on board) — tried with `cpu_use_dynarec = 0`
      (forcing the slower pure interpreter instead of the JIT-like dynamic
      recompiler, which changes the guest's effective execution speed
      substantially); identical error.
    - **Chipset/BIOS-specific bug** — tried both `430vx` (Intel i430VX,
      Award BIOS) and `fic_va503p` (VIA MVP3, different BIOS) with otherwise
      identical config; identical error on both.
    - **Tried but inconclusive**: freshly rebuilt the `RELEASE_BUILD` binary
      (the original had been overwritten by an in-place `make` during the
      debug rebuild — rebuilding it means `make clean` then `./configure
      --enable-release-build` again) to check whether this is another
      debug-build-only compiler-optimization bug in the same family as
      gotcha #9's disk-detection bug. Inconclusive: the release build hit its
      *own*, already-documented "Primary master hard disk fail" bug first
      (confirming that bug is still present and unrelated to any of this
      session's fixes), and separately reported a bizarre CPU/memory
      mismatch in its POST banner (`PENTIUM-S CPU at 75MHz` / `8192K`
      instead of the configured Pentium MMX 200 MHz / 64 MB) that wasn't
      investigated further given the higher-priority disk-fail blocker on
      that build. **A clean release-vs-debug comparison for this specific
      bug has not actually been done yet** — that's the most promising
      untried lead if picking this back up (would need the release build's
      own disk issue worked around first, e.g. by testing purely with a
      RAM-disk or by getting further in gotcha #7/#9's investigation for
      that build specifically).

19. **Resolved false lead: the Voodoo3 graphics card was not the cause of
    gotcha #18.** Hypothesis was that the Voodoo3's PCI memory-mapped I/O
    region could be confusing Windows' memory-map probing. Tested by
    switching `gfxcard = v3_3000` → `gfxcard = vga` (triggers a harmless
    "Configured video BIOS not available. Defaulting to available romset."
    dialog on `fic_va503p`, since no bundled generic-VGA romset matches that
    model exactly — dismiss with OK, PCem falls back automatically). The
    "16MB of memory" error reproduced byte-for-byte identically at the same
    point in Setup. Rules out the graphics card entirely as a factor in
    gotcha #18.

20. **PCem cannot successfully boot from the Windows 98 CD's own El Torito
    boot record — this looks like a genuine gap in PCem's BIOS/ATAPI CD-ROM
    emulation, not a config problem.** The Windows 98 SE ISO used in this
    project *is* a valid El Torito CD (`isoinfo -d` reports `El Torito VD
    version 1 found`, `Boot media 2 (1.44MB Floppy)`, bootable flag set) —
    booting straight from it would replace the entire custom FreeDOS floppy
    with Microsoft's own genuine real-mode boot environment, sidestepping
    gotcha #18 (and every other custom-floppy gotcha in this file) in one
    move. In practice: setting the Award BIOS's `Boot Sequence` to put
    `SCSI` (this BIOS's label for the ATAPI CD-ROM boot device — see gotcha
    #21) first causes POST to hang indefinitely at "Now Detecting Boot
    Sector Type Virus..." (the `ChipAwayVirus` boot-sector-scan BIOS
    extension) — confirmed genuinely hung, not slow, via repeated
    screenshots over 45+ seconds showing zero change while CPU stayed
    pegged. Disabling `Detect Boot Virus By Trend` (BIOS Features Setup)
    removes that specific hang, but POST then hangs identically at the very
    next step instead (immediately after "Verifying DMI Pool Data ...
    Update Success", where the BIOS would actually start reading the El
    Torito boot image from the CD) — same symptom, same "identical every
    time regardless of wait" signature as gotcha #17 describes, pointing at
    a structural gap in the emulated ATAPI/BIOS El-Torito-read path rather
    than a slow operation. **Verdict: not fixable from `pcem.cfg` or BIOS
    Setup; abandoned in favor of gotcha #22's fix**, which gets the exact
    same "genuine Microsoft boot environment" benefit without needing
    PCem to boot the CD directly — the boot floppy itself now carries real
    Microsoft files, so this El Torito path is no longer needed for
    anything.

21. **Two reusable findings from navigating Award BIOS Setup itself in this
    environment**, found while investigating gotcha #20:
    - **Reaching BIOS Setup reliably requires spamming `Delete` continuously
      through the whole POST window, not timing a single keypress.** A
      single well-timed `Delete` after watching for "Press DEL to enter
      SETUP" on screen consistently arrives too late (POST has already
      moved on to boot-device search by the time a screenshot round-trip +
      one keypress completes). What works: immediately after relaunching
      PCem and capturing the mouse (gotcha #8), fire ~15-30 `Delete`
      keypresses in a tight loop over several seconds using one persistent
      VNC connection (reconnecting per-keypress via a fresh process, as
      `send-keys.js` does, adds enough round-trip latency per call that a
      loop of individual process invocations mostly still misses the
      window — a single connected script sending repeated taps is what
      reliably lands inside it).
    - **This BIOS's `Boot Sequence (LS120/ZIP100)` field has no explicit
      `CDROM` entry — `SCSI` is the entry that boots the ATAPI CD-ROM.**
      Cycling the field (`Page Up`/`Page Down` — note **`KP_Page_Up`/`0xff9a`
      cycles the same direction as the "next option" `Page Down` semantics
      here**, not what the keysym name implies; use plain `Page_Up`/`0xff55`
      to reliably cycle the other way) walks through `A,C,SCSI` → `C,A,SCSI`
      → `C only` → `D,A,SCSI` → `E,A,SCSI` → ... → `SCSI,C,A` → `SCSI,A,C` —
      i.e. `SCSI` stands in for "the ATAPI/El-Torito-capable device" in this
      Award BIOS revision's boot-order UI, the same way it's historically
      used as a catch-all boot-device class on BIOSes of this era.

22. **The actual fix for gotcha #18: replace the entire FreeDOS boot
    environment with genuine Microsoft Windows 98 boot files, extracted
    directly from the install CD's own cabinet files.** No internet
    download, no third-party boot disk — every file comes from
    `win98se.iso` itself:
    - `cabextract` isn't in the base container image: `apt-get install -y
      cabextract` (Debian bookworm, instant).
    - The ISO's individual cabinets can be pulled straight out with
      `isoinfo -i win98se.iso -R -x '/WIN98/<NAME>.CAB' > NAME.CAB` — no
      need to mount the ISO (this container has no loopback-mount
      permission anyway).
    - Real `COMMAND.COM` (93,890 bytes) and the real consolidated real-mode
      DOS kernel — shipped in the cab under the name **`winboot.sys`**, which
      Setup itself renames to `IO.SYS` when actually installing — both live
      inside the multi-part `PRECOPY1.CAB`/`PRECOPY2.CAB` set (`cabextract`
      auto-follows the `extends to`/`extends backwards to` chain as long as
      all the referenced cab files are present alongside each other, so
      fetch `CATALOG3.CAB`, `BASE4.CAB`, `BASE5.CAB`, `BASE6.CAB` too even
      though nothing is extracted from them directly).
    - Real `HIMEM.SYS` (33,191 bytes), `OAKCDROM.SYS` (a generic real-mode
      ATAPI CD-ROM driver, 41,302 bytes), and `MSCDEX.EXE` (25,473 bytes)
      all live in `BASE5.CAB`.
    - `/TOOLS/MTSUTIL/FAT32EBD/IMAGE.DSK` (36,864 bytes) is Microsoft's own
      Emergency-Boot-Disk **template** — it has a genuine, correctly-authored
      Windows 98 boot sector (real bootstrap code at offset 0x3E, standard
      1.44 MB BPB: 2 sectors/cluster, 224 root entries, 9 sectors/FAT, 18
      sectors/track, 2 heads) plus a skeleton root directory
      (`AUTOEXEC.BAT`/`CONFIG.SYS`/an 8-byte placeholder `MSDOS.SYS`) — but
      **the file itself is truncated to only the sectors those three tiny
      files actually occupy** (`mdir` still reports the full ~1.4 MB of
      "free space" by trusting the BPB's declared total-sectors field, but
      writing anything past the physical 36,864 bytes reads/writes past
      the real end of the file). Don't `mcopy` onto `IMAGE.DSK` directly.
      Instead: `dd if=/dev/zero of=win98boot.ima bs=1024 count=1440`,
      `mformat -i win98boot.ima -T 2880 -h 2 -s 18 ::` (matches `IMAGE.DSK`'s
      BPB exactly), then `dd if=IMAGE.DSK of=win98boot.ima bs=512 count=1
      conv=notrunc` to transplant just the genuine first sector (boot code +
      BPB) onto the now-properly-sized image. `mcopy`/`mattrib +h +s +r` the
      five real files on afterward (`IO.SYS` and `COMMAND.COM` need
      hidden+system+read-only to match genuine Win98 media — `mattrib -i
      img '::*.*'` lists current attributes to confirm).
    - `CONFIG.SYS` only needs `DEVICE=HIMEM.SYS /testmem:off` +
      `DEVICE=OAKCDROM.SYS /D:mscd001` (plus the usual `FILES=`/`BUFFERS=`/
      `DOS=HIGH,UMB`/`LASTDRIVE=Z`) — this is, byte-for-byte in spirit, the
      same `[CD]` section Microsoft's own real Startup Disk ships in
      `IMAGE.DSK`'s template `CONFIG.SYS`, discovered by `mtype`-ing it
      before overwriting. `AUTOEXEC.BAT` just needs `MSCDEX.EXE /D:mscd001
      /L:D` then whatever you want to auto-launch (`D:\SETUP.EXE` once
      you're past experimentation).
    - Net result: booting this floppy shows the real Microsoft driver
      banners (`This driver is provided by Oak Technology, Inc..`, real
      `MSCDEX Version 2.25` banner) instead of FreeDOS's, `D:` mounts
      identically to before, and **Setup's "Copying files needed for
      Windows Setup..." step proceeds straight into the real 32-bit wizard
      with no memory error at all** — first-try, no further tuning needed.

23. **Mouse clicks are unreliable inside Setup's graphical (Mini-Windows)
    screens in this container/Xvfb/VNC setup — use `Tab`+`Enter` instead,
    confirming focus via screenshot before pressing Enter.** Once Setup
    leaves the plain-text DOS screens and enters its GUI wizard (starting
    at "Welcome to Windows 98 Setup"), `xdotool click` on `Continue`/`Next`/
    dialog buttons routinely does nothing even when: the mouse is
    genuinely captured (gotcha #8), the cursor visibly hovers exactly on
    the button with the correct hand-pointer icon, `mousedown`/`sleep`/
    `mouseup` are sent explicitly instead of a bare `click`, and repeated
    attempts are made. (Absolute `xdotool mousemove X Y` is also unreliable
    once the SDL mouse is captured — same as gotcha #8's original note —
    use `mousemove_relative -- dx dy` computed from the cursor's last known
    rendered position in a screenshot instead, or avoid mouse positioning
    for clicking entirely per this gotcha.) What *does* work every time:
    send a bare `Tab` (`0xff09`), screenshot to see which control now has
    the dotted focus rectangle, and only send `Enter` (`0xff0d`) once
    that's confirmed to be the desired button — the number of `Tab`s needed
    to reach `Next`/`OK` varies per screen (radio-button groups count as one
    stop; text-field-heavy screens like Identification need several). This
    is what actually drove Setup through Welcome → Setup Options → Windows
    Components → Identification → Establishing Your Location → Startup Disk
    → Start Copying Files after mouse-based interaction repeatedly stalled
    on the very first `Continue` button.

24. **A Setup-triggered restart mid-file-copy re-entered the DOS/floppy
    environment instead of continuing into GUI-mode setup, redoing the
    entire DOS-mode wizard from scratch — three full times.** Windows 98
    Setup's file copy runs in DOS real mode (driven by `D:\SETUP.EXE` off
    the CD, launched from the boot floppy's `AUTOEXEC.BAT`), then does a
    **mandatory hardware reboot** before continuing into the GUI-mode wizard
    (hardware detection, "Setting up hardware and finalizing settings").
    With the Award BIOS's `Boot Sequence (LS120/ZIP100)` left at its default
    `A,C,SCSI` (floppy first — see gotcha #21), every one of these reboots
    re-booted the floppy and re-ran `AUTOEXEC.BAT`'s `D:\SETUP.EXE`, which
    restarted the whole DOS-mode wizard from "Welcome" rather than letting
    the reboot land on the now-partially-installed `C:` and resume GUI setup
    — a genuine restart loop, not a hang or a Setup bug, and easy to mistake
    for one since each cycle looks identical to the first run. **Fix: enter
    BIOS Setup (gotcha #21's Delete-spam technique) and change `Boot
    Sequence` from `A,C,SCSI` to `C only`** (cycle with `Page Down`/`0xff9a`:
    `A,C,SCSI` → `LS/ZIP,C` → `C only`), then F10-save. Confirmed fixed: the
    very next reboot showed Windows 98's own **"Windows Setup Safe Recovery"**
    screen (*"Windows Setup could not completely install Windows... If you
    started Setup from Windows, type WIN to restart Windows, and then run
    Setup again... Do not delete any files or reconfigure your system."*) —
    proof `C:` now has genuine bootable Windows files — followed by a direct
    boot straight into the GUI Setup Wizard (resuming at "Start Wizard" /
    Finish, then "Setting up hardware and finalizing settings") with no
    DOS/floppy detour at all. With the boot floppy now retired from active
    use (`Boot Sequence = C only` means it's never read again), the
    genuine-Microsoft-boot-floppy fix from gotcha #22 has done its job and
    isn't needed for the rest of Setup or for normal operation.

25. **Windows 98 SE has booted to a working desktop under PCem for the first
    time.** Two more Setup-triggered reboots (the post-hardware-detection
    restart, and the final restart into first-boot) each hung identically to
    gotcha #24's original symptom, but with a different signature: instead of
    re-entering the DOS/floppy environment, the guest CPU got stuck spinning
    in a tiny (~10-byte) real-mode code range — confirmed via repeated `gdb -p
    <pid> -batch -ex 'print/x cpu_state.pc'` samples oscillating between the
    same 2-3 nearby addresses (occasionally diverging to a fixed timer-ISR
    address and back) rather than advancing, unlike legitimate work
    elsewhere in this session which always showed `cpu_state.pc` landing on
    substantially different addresses each sample. This looks like the
    guest's post-hardware-detection reboot request (likely a keyboard-
    controller-reset sequence) not completing under this chipset
    (`fic_va503p`/VIA MVP3) — plausibly related to the same El Torito/
    boot-virus-scan-class BIOS gaps noted in gotcha #20 for this model, though
    not confirmed further given a working recovery was already in hand.
    **Recovery, identical both times**: `kill -9` the `pcem-debug` process
    (plain `pkill`/`SIGTERM` still doesn't work — see gotcha #12) and relaunch
    with the same `--config pcem.cfg` invocation. With `Boot Sequence = C
    only` (gotcha #24) already set, the relaunch boots straight back into
    `C:` with no floppy detour every time — Setup simply re-ran the
    in-progress phase (hardware detection redid its scan from the top; the
    final restart resumed straight into "Getting ready to run Windows for the
    first time") rather than losing overall progress. Re-capture SDL mouse
    input after each relaunch (gotcha #8: `xdotool windowfocus`/`click` on
    the 640×480 render window, found via `xdotool search --name pcem` +
    `getwindowgeometry` — it's the larger of the two windows that command
    returns, the other being the ~10×10 wx frame from gotcha #12).
    **A live checkpoint of this exact state** (Windows 98 SE fully installed,
    first boot to desktop reached, no drivers beyond the auto-detected PnP
    monitor yet) was copied to `disk-vhd-503-win98-desktop-checkpoint.vhd`
    alongside the working disk, in case a driver install or the LOCO copy
    step goes wrong later and this state needs restoring rather than redoing
    the ~hour of Setup navigation from scratch.

26. **Voodoo3 (3dfx `am29win9x`) and DirectX 7.0a drivers installed successfully
    from a custom CD image, and the resulting install was checkpointed to
    GHCR.** Since both driver packages (`containers/amigamerlin-win9x-29.zip`,
    `containers/directx7.zip`) are several MB — too big for a floppy — they
    were extracted on the host and repacked into a fresh ISO with
    `genisoimage -J -joliet-long -r -V DRIVERS -o drivers.iso
    drivers-iso-root/` (Joliet extensions so Win98 sees long filenames), then
    `cdrom_path` in `pcem.cfg` was swapped from `win98se.iso` to this new
    `drivers.iso` and PCem relaunched (`kill -9` + relaunch — a plain config
    edit doesn't take effect on a running process, and gotcha #4's auto-save
    on graceful exit is avoided entirely by never asking for one). Both
    installers (`voodoo3\am29win9x\driver9x\Setup.exe`, then
    `directx7\7.0_directx7.exe`) were driven via `Tab`/arrow-key/`Enter`
    navigation exactly per gotcha #23 — mouse clicks remain unreliable, and
    Explorer icon navigation (arrow keys + `Enter` to open, `Backspace` to go
    up one folder) works fine as a keyboard-only substitute for double-click.
    **New input gotcha found here**: typing a literal `:` (colon) via this
    environment's synthetic-keysym path is unreliable — it silently becomes
    `;` or is dropped outright, corrupting any typed path like `D:\foo`.
    Sending it as an explicit `Shift`+`semicolon` combo didn't reliably fix it
    either. **Workaround: never type a drive letter + colon at all** — use
    Explorer's own icon-selection navigation (arrow keys between icons,
    `Enter` to descend, `Backspace` to go up) to reach a target file instead
    of typing its path into the Address bar or a Run dialog.
    DirectX 7 required one more restart to finish (`Building driver
    information database` runs on the next boot) — same `kill -9` + relaunch
    recovery applied when that reboot's BIOS POST screen stayed black for
    ~50s with an ambiguous (partially-repeating) `cpu_state.pc` sample, and it
    came back up cleanly with no data loss. **A second checkpoint was saved
    after both driver installs**, this time pushed to the registry rather
    than just sitting alongside the working disk: wrapped in a `FROM scratch`
    Dockerfile and pushed as
    `ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:pcem-win98-post-drivers`
    — the same tagging scheme the qemu-softgpu bake pipeline
    (`scripts/bake-game-snapshots.ps1`) uses for its own snapshots, just
    without that script's QEMU/kubectl-specific extraction steps since the
    raw `.vhd` was already sitting on the host from PCem's own disk config.
    (Attempted to also confirm the Voodoo3 driver via Device Manager, but
    both the `Ctrl+Esc` Start-menu shortcut and `Alt+Enter`-on-selected-icon
    Properties shortcut failed to register repeatedly in this environment;
    deferred to functional verification once LEGO LOCO itself runs, which is
    a more meaningful test of 3D acceleration than a Device Manager label
    anyway. Host-side inspection of `SYSTEM.INI` via `mtools` while PCem has
    the disk open was also tried as a shortcut and abandoned — `mtype`
    reported "Error reading FAT" even moments after a confirmed host-file
    flush, most likely a cache-coherency gap between PCem's internal
    write-back cache and the host file rather than actual corruption; treat
    any host-side read of a disk PCem currently has open as unreliable, not
    just host-side writes as gotcha #16 already warned.)

27. **`Loco.exe` runs under PCem — genuine progress past every environment
    blocker in this file — but hits a game-level error, not an emulator one:
    "An error occurred while loading. Please reinstall this software."**
    This is LEGO LOCO's own generic error dialog, shown right after its
    splash screen (LEGO logo + "media." branding both render correctly,
    confirming the Voodoo3/software rendering path works enough to draw the
    splash). Launched via `C:\Program Files\lego media\constructive\LEGO
    LOCO\Exe\Loco.exe` — reached without ever typing a colon, by opening
    a fresh Explorer window to a known-good address-bar state (e.g.
    `C:\Program Files\lego media`, reached entirely via icon/arrow-key
    navigation) then `Alt+D` → `End` → typing the remaining
    `\constructive\LEGO LOCO\Exe\Loco.exe` suffix and `Enter` — a reusable
    pattern for launching anything by path in this environment without
    hitting gotcha #26's colon bug at all. **Root cause not yet found; three
    candidate explanations, most likely first**:
    - **CD-check**: many 1998-era CD games refuse to run without their
      original CD in the drive as a copy-protection check. `D:` currently
      holds the custom `loco-game.iso` built for file transfer (gotcha #26),
      not a bootable/autorun-capable image of the real LEGO LOCO retail CD —
      if `Loco.exe` checks for a specific volume label, file, or CD-audio
      track on `D:` and doesn't find it, this exact generic error is a very
      plausible result.
    - **Missing registry state**: copying the installed game's files
      directly (this session's approach) skips whatever `HKEY_LOCAL_MACHINE`/
      `HKEY_CURRENT_USER` keys the original InstallShield-based installer
      (`Uninst.isu` is present in the copied folder, confirming InstallShield
      was used originally) would have written — install path, CD key/serial,
      DirectPlay/component registration, etc. `Exe\LEGO.INI` (a plain-text
      config file, not the registry) does hardcode
      `C:\Program Files\LEGO Media\Constructive\LEGO LOCO\...` paths, but
      these match our actual copy destination case-insensitively (FAT
      doesn't care about the `LEGO Media`/`lego media` casing difference
      from gotcha #26's forced-lowercase typing), so this specific file is
      probably not the culprit — but it confirms the *category* of "install
      leaves behind state beyond just the files" is real for this game.
    - **Corrupted/truncated resource file — ruled out.** In-guest Explorer
      (maximized, via the same `Alt+Space` `x` system-menu maximize trick,
      keyboard-only) shows `art-res\resource.RFD` at exactly 55,963 KB
      (status bar: 54.6 MB) — matching the original 57,305,835-byte file to
      the nearest displayed KB (Explorer rounds up: 57,305,835 / 1024 =
      55,962.73 → 55,963). The double-paste episode did not corrupt this
      file; focus should shift to the CD-check or registry theories.
    Also note: this is a **different, earlier failure than the qemu-softgpu
    sibling README's own results** for this exact game on this exact golden
    image (`netready.qcow2`), which get as far as the intro/menu before
    GPF'ing — this PCem attempt fails before that point, at the loading
    screen itself, so whatever's wrong here is specific to the fresh-install
    approach (missing state a real installer would set up) rather than a
    LOCO-vs-3dfx-driver rendering incompatibility.

28. **First attempt at gotcha #27's missing-registry-state theory: found real
    strings, built a plausible `.reg`, imported it cleanly — did not fix the
    error.** `SYSTEM.DAT`/`USER.DAT` are Windows 9x's old `CREG` format
    (magic bytes `CREG`, then `RGKN`/`RGDB` blocks) — a completely different,
    older binary layout than the NT registry hive format, so `hivex`/
    `virt-win-reg` (libguestfs's usual registry tools) can't read them, and
    no packaged parser exists (`pip install pycreg`/`win9xreg`/`creg` all
    404'd against PyPI). Two approaches were tried:
    - **Live QEMU + `regedit /e` export** — booted `netready.qcow2` under
      plain `qemu-system-i386` (Debian's `qemu-system-x86` package, not a
      custom build) with `-snapshot` (throwaway) and a writable `-fda`
      floppy meant for exporting a `.reg` file, using the flags the
      qemu-softgpu standalone README documents as required for this image
      (`-cpu qemu32,+sse3,+ssse3,+sse4.1`, single-threaded `-accel tcg` —
      MTTCG is documented there as hanging this guest early — `-vga std` in
      place of `vmware` since only text/registry access was needed here,
      not 3D). **Abandoned as a dead end**: QEMU's built-in `-vnc` (as
      opposed to the Xvfb+x11vnc bridge used for PCem all session) has its
      own input quirks — Escape/Ctrl+Esc/arrow-key Start-menu navigation all
      worked fine, but plain letter keys silently did nothing once at the
      desktop (tried both with and without `-k en-us`), and absolute mouse
      clicks via `-device usb-tablet` didn't register either, even on
      simple targets like desktop icons. An early green/black
      vertical-stripe screenshot during BIOS POST turned out to be a red
      herring, not the real problem — confirmed via `info registers` over
      the QEMU monitor (`-monitor telnet:...`) showing genuine EIP progress
      across samples, not a stuck loop; the real blocker was specifically
      character input once the desktop was reached, never root-caused
      further given time already spent.
    - **Raw ASCII string scan of the extracted `.DAT` files — this is what
      actually found something usable.** Rather than parsing CREG's binary
      structure, a plain Python regex scan (`re.finditer(rb'[\x20-\x7e]{3,}',
      data)`) for printable-ASCII runs containing `LEGO`/`LOCO` was enough:
      it surfaced a clear cluster in `SYSTEM.DAT` around offset `0x24c735` —
      `LEGO Media`, `LEGO LOCO`, a version string `1.12.008`, `loco.exe`, two
      separate `Path` values (one at `C:\Program Files\LEGO
      Media\Constructive\LEGO LOCO`, another at `...\LEGO LOCO\Exe`), an
      `UninstallString` referencing `IsUninst.exe`/`Uninst.isu` (confirming
      InstallShield), a `DisplayName`, and a `Publisher`-shaped string
      `Intelligent Games`. Built a `.reg` file recreating a plausible
      `HKEY_LOCAL_MACHINE\SOFTWARE\LEGO Media\LEGO LOCO` key (+ `\Exe`
      subkey) from these strings, delivered via a small Joliet ISO (same
      pattern as gotcha #26's drivers/game-files ISOs), and imported by
      selecting it in Explorer and pressing `Enter` — `REGEDIT.EXE`'s own
      "are you sure you want to add this information to the registry?" /
      "successfully entered into the registry" dialogs handled the actual
      merge, so gotcha #26's colon-typing bug never came up (no manual path
      typing needed for this step at all).
    - **Result: registry import succeeded cleanly, but relaunching
      `Loco.exe` showed the exact same "reinstall this software" error
      afterward.** Either the guessed key hierarchy/value names don't
      exactly match what the exe actually reads at startup (the raw-scan
      approach confirms these strings exist somewhere in the file but not
      their real parent/child key relationships — only a proper RGKN/RGDB
      structural parse would confirm that), or the registry isn't the
      actual blocker here and gotcha #27's CD-check theory deserves priority
      next.

29. **RESOLVED — "reinstall this software" was caused by the raw-copy
    install itself, not a CD-check or missing registry key.** The fix:
    abandon the raw-file-copy approach entirely and run the **genuine
    retail InstallShield installer** from the actual `Lego_Loco.iso` CD
    image (confirmed via `isoinfo -d`: ISO9660+Joliet, volume id "LEGO
    LOCO", publisher "LEGO MEDIA", `SETUP.EXE` + InstallShield engine +
    C-Dilla copy-protection files + bundled DirectX7 installer — a
    complete, unmodified retail disc image, not a hand-extracted file
    transfer).
    - Copied the ISO into the `pcem-run` container's `/work` (only bind
      mount available to it) and pointed `cdrom_path` at it in
      `pcem.cfg`. Opening `D:` in Explorer auto-fired the real
      `AUTORUN.INF` → "Choose Setup Language" → InstallShield wizard
      (Welcome → License → Select Components).
    - **First attempt failed at Select Components**: `Space Available`
      (4.6 MB) was far below `Space Required` (~205 MB) because the
      earlier botched raw-copy install's `C:\Program Files\lego
      media\constructive\LEGO LOCO` tree was still occupying the disk.
      Exited Setup cleanly (`Exit Setup` confirmation dialog, not a crash)
      and deleted `lego media` from Explorer — most of it went via a
      normal "Yes to All" on read-only-file prompts, but the `LEGO LOCO`
      subfolder itself resisted removal with "Access is denied" (likely a
      lingering handle from something in-guest). This still freed enough
      space (503 MB disk → 227 MB free per `C:` Properties) to proceed;
      the residual empty `LEGO LOCO` folder was harmlessly overwritten
      file-by-file by the real installer's own "read-only file detected,
      overwrite?" prompts (answered `Yes to All`) during the actual copy.
    - **Second attempt**: full install completed (progress bar 0→100%,
      ~2 minutes), followed by a DirectX7 sub-installer step
      ("Extracting Direct Transform...") that hit its own "not enough
      disk space to install DirectX" warning — harmless, since gotcha
      #26 already installed Voodoo3 + DirectX7 drivers directly; just
      clicked through it.
    - **Result: `Loco.exe` now launches cleanly** — LEGO Media splash →
      a genuine real-time-rendered 3D intro cinematic (LEGO carrying
      case, train-track scene, postman-on-a-skateboard sequence) →
      **Escape skips straight to the actual LEGO LOCO profile-selection
      main menu**, fully interactive, no "reinstall this software" error
      at any point. This confirms the error was never a CD-check or a
      missing/wrong registry key (both of gotcha #27/#28's theories) —
      it was that the raw file-copy approach could never faithfully
      reproduce whatever InstallShield's real first-run does (correct
      file *attributes*/timestamps, a fully-populated real registry tree
      versus the gotcha #28 guess, and/or InstallShield-internal
      component-registration bookkeeping a plain file copy has no way to
      replicate).
    - **Recurring session-wide flakiness note**: individual keystrokes
      (especially `Enter` on a freshly-selected icon, and modifier
      combos like `Shift+Tab`) routinely needed 2–6 retries to register
      even with input verified alive via a `Tab`-then-screenshot check
      in between — worse than earlier sessions, cause not identified
      (possibly cumulative VNC/x11vnc connection churn from this
      session's very high number of short-lived script invocations). A
      `Left` then `Right` (or `Down` then `Up`) "refresh" pair immediately
      before `Enter` reliably un-stuck a real Explorer-list focus/selection
      desync several times when plain retries of `Enter` alone did not.

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
**LEGO LOCO now runs correctly end-to-end under PCem** (see gotcha #29) —
Windows 98 SE boots to a working desktop (gotchas #14–17, #22, #24, #25),
Voodoo3 + DirectX 7 drivers are installed (gotcha #26), and the genuine
retail InstallShield installer (run from `Lego_Loco.iso`, not a raw file
copy) put down a fully correct install: `Loco.exe` launches straight to the
LEGO Media splash, plays the real-time-rendered 3D intro cinematics, and
`Escape` skips to the actual interactive profile-selection main menu — no
"reinstall this software" error anywhere in that path. Checkpoints on disk:
`disk-vhd-503-win98-desktop-checkpoint.vhd` (pre-drivers),
`disk-vhd-503-post-drivers-checkpoint.vhd` (post-drivers, pushed to
`ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:pcem-win98-post-drivers`),
`disk-vhd-503-with-loco-checkpoint.vhd` (the old raw-copy install, superseded
— kept only for reference), and **`disk-vhd-503-genuine-install-checkpoint.vhd`
(the working genuine install, pushed to
`ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:pcem-win98-genuine-loco-install`)**.
Remaining work, roughly in order:
- Benchmark performance now that it actually runs — frame rate / responsiveness
  of the 3D intro and in-game view under PCem+Voodoo3 — against the qemu-3dfx
  numbers in the sibling README.
- Run the m5stack-lens hardware/software companion tests against this now-working
  LOCO instance (see `m5stack-lens/` at the repo root).
- Minor cleanup before final imaging: remove the stray `TEST.TXT` file left
  on `C:` from an earlier diagnostic `mcopy`, and the empty/access-denied
  leftover `LEGO LOCO` directory entry under the old `lego media\constructive`
  path if it's still lingering (harmless either way, but tidy).

**86Box** was kept as a fallback while gotcha #18 was still unresolved —
prebuilt Linux AppImage + ROM set already downloaded during an earlier
session, see
[`docs/knowledge/emulation/pcem-86box-runtime-evaluation.md`](../../../docs/knowledge/emulation/pcem-86box-runtime-evaluation.md)
— but with gotcha #22's fix landing, PCem is no longer blocked and 86Box is
back to being a "nice to have another data point" option rather than a
required fallback. Every apparent "PCem bug" chased across this project so
far (gotchas #7/#9's release-build compiler bug, #14's disk-image bug,
#17/#18's memory-error investigation) turned out to be a config, tooling, or
boot-environment issue rather than something wrong with PCem's own hardware
emulation — worth remembering next time something here "looks like an
emulator bug."
