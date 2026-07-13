# Standalone PCem test — evaluating PCem/Voodoo3 for LEGO LOCO

Bring-up log for testing whether **PCem** (real period-hardware emulation,
software Voodoo3 dynarec) can run LEGO LOCO more smoothly than QEMU+SoftGPU or
qemu-3dfx. See [../../qemu-softgpu/standalone/README.md](../../qemu-softgpu/standalone/README.md)
for the QEMU-side investigation this follows on from.

## TL;DR (updated — third session)
- **Disk and CD-ROM are both fully working now** (see below) — Windows 98 SE
  Setup successfully boots from CD, launches, and gets as far as copying its
  initial files. **Blocked on a new, unresolved issue**: Setup's 32-bit
  wizard shows "Windows 98 requires a computer with at least 16MB of memory"
  during the file-copy step, every time, unconditionally — see gotcha #18.
  Tried and ruled out as the cause: `mem_size` (65536 and 32768 both fail
  identically), the `JEMM386`/EMS-UMB memory manager (fails identically with
  it removed, `HIMEMX`-only), a stale/bad CMOS (fails identically after
  deleting the NVR file to force fresh auto-detection), `cpu_use_dynarec`
  (fails identically with the dynamic recompiler off), and the machine model
  (fails identically on both `430vx`/Award BIOS and `fic_va503p`/VIA MVP3 —
  two different BIOS vendors). Not yet isolated further; see gotcha #18 and
  "Next steps" for the state of this.
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
**The disk/IDE and CD-ROM bugs are resolved (see TL;DR + gotchas #14–17) —
PCem + either machine model + the debug build + a correctly-configured disk
and CD-ROM all work.** Currently blocked on gotcha #18 (Setup's false "16MB
of memory" error) before Windows 98 can actually finish installing:
- **Most promising untried lead**: a clean release-vs-debug-build comparison
  for gotcha #18 specifically. The release build's own pre-existing disk-fail
  bug (gotcha #7, still present, confirmed again this session) blocked a
  clean test. If the release build's disk-fail bug can be worked around for
  just long enough to reach the Setup memory check — e.g. temporarily via a
  disk config known to dodge it, or by getting further in isolating gotcha
  #7 itself for a fresh look — and the memory error does *not* reproduce
  there, that would point conclusively at another debug-build-only
  compiler-optimization bug (same family as gotcha #9), likely somewhere in
  extended-memory/E820-style reporting rather than IDE this time.
- Try `patch9x`'s `-force-cpupatch`/`-force-cpupatch-ndis` options against
  the Windows 98 install media itself (the tool's help text implies it can
  target "a directory with windows instalation", not just an already-installed
  system) — untried this session, and it's the exact tool this floppy bundles
  for "fix CPU issues," even though gotcha #18's dynarec-off test argues
  against a pure CPU-speed cause.
- Consider whether the *win98se.iso* itself (not the emulator or disk) is
  implicated — e.g. a slipstreamed/OEM build with an unusual `MSBATCH.INF` or
  a modified `w98setup.bin`, since this error is normally hardware-triggered
  and we've now ruled out every hardware-shaped explanation tried so far.
  Not yet checked: whether a *different* Windows 98 (SE or first edition) ISO
  hits the same wall.
- Once Setup completes: install chipset drivers, Voodoo3 drivers (from
  `containers/amigamerlin-win9x-29.zip`), and DirectX 7
  (`containers/directx7.zip`); copy the LEGO LOCO game files over (no
  standalone installer in the repo — copy `Program Files\LEGO
  Media\Constructive\LEGO LOCO\` from the existing golden qcow2 image);
  benchmark performance (the original point of this investigation) against
  the qemu-3dfx numbers in the sibling README; snapshot the finished disk
  into the existing bake pipeline (`scripts/bake-game-snapshots.ps1` pattern)
  and publish under a new tag.

**86Box** remains a reasonable fallback if gotcha #18 turns out to be a
genuine, unfixable-from-config PCem bug — prebuilt Linux AppImage + ROM set
already downloaded during this session, see
[`docs/knowledge/emulation/pcem-86box-runtime-evaluation.md`](../../../docs/knowledge/emulation/pcem-86box-runtime-evaluation.md).
Given how much of this session's *other* apparent "PCem bugs" turned out to
be config/tooling issues instead (gotchas #14, #17), it's worth exhausting
the release-vs-debug comparison and the ISO-variant check above before
concluding this one is really PCem's fault.
