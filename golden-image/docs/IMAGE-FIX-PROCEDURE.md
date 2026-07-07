# Fixing a dirty snapshot into a clean golden image

How the `emulator-snapshot:hostgame` / `:joingame` qcow2 (which booted into
ScanDisk + a recurring PnP Monitor wizard + a Tray3d crash) was turned into a
clean, sealed golden image — reproducibly and headlessly (QMP, no GUI human).

Result (measured 2026-07-07): `win98-loco-golden:safe512-v1`
- sha256 `9e8ad542963335b2b8d7955d8b2d6c99315724860c863e3448bc30d1e4f4c058`
- 516 MB compressed, standalone qcow2, `qemu-img check` clean (leaks repaired).
- Boots **straight to the Windows desktop**: no ScanDisk, no driver wizard, no
  Tray3d crash (evidence: `evidence/fixed-clean-boot-t60.png`, `...-t160.png`).

## Root causes (see GHCR-SNAPSHOT-VALIDATION.md)
1. Captured from a dirty (running) state → "Windows was not properly shut down"
   → ScanDisk every boot, and a corrupted registry.
2. The PnP "Plug and Play Monitor" driver was never committed (every prior boot
   was ephemeral `-snapshot`), so the Add-New-Hardware wizard recurred.
3. `Tray3d.exe` (SoftGPU 3dfx tray applet) crashes under `-vga std` (no 3dfx).

## Procedure (what the fix run did)

1. **Boot WRITABLE** (persistent, not `-snapshot`) so changes stick:
   ```
   qemu-system-i386 -M pc -cpu pentium3 -m 512 -smp 1 \
     -blockdev driver=file,filename=work.qcow2,node-name=lf,auto-read-only=off \
     -blockdev driver=qcow2,file=lf,node-name=ld \
     -device ide-hd,drive=ld,bus=ide.0,unit=0 \
     -vga std -display vnc=127.0.0.1:1 -qmp unix:/tmp/qmp.sock,server,nowait -no-shutdown
   ```
2. **Let ScanDisk finish.** Windows' Registry Checker then reported a corrupt
   registry and restored a good backup → Enter to restart (this clears the
   corruption). Drive via QMP: `sendkey ret`.
3. **Complete the PnP Monitor wizard** (drives via QMP `sendkey`): Next →
   "Search for the best driver" → **uncheck "Floppy disk drives"** (Space) so it
   doesn't stall on empty A: → Next → it finds `C:\WINDOWS\INF\MONITOR.INF`
   (built-in, no CD) → Next → Finish. Now committed; it won't recur.
4. **Disable Tray3d offline** (it launches from an HKLM Run key; the exe crashes).
   Rename it so Windows silently skips the missing target:
   ```
   guestfish -a work.qcow2 : run : mount /dev/sda1 / \
     : mv /WINDOWS/SYSTEM/TRAY3D.EXE /WINDOWS/SYSTEM/TRAY3D.EX_
   ```
   NOTE: an offline FAT edit re-sets the volume-dirty flag, so do this BEFORE the
   final clean boot, not after.
5. **One more writable boot** so that ScanDisk pass clears the offline-edit
   dirtiness, and confirm the desktop is clean (no wizard, no Tray3d).
6. **Clean shutdown** via the Start menu (QMP): `ctrl-esc`, `up`, `ret`, `ret`.
   QMP `query-status` must report `"status": "shutdown"` — that clean powerdown
   clears the dirty flag so the next cold boot skips ScanDisk.
7. **Seal**: `image/seal-golden-image.sh work.qcow2 out/win98-loco-golden-safe512.qcow2 safe512`
8. **Verify**: boot the sealed image `-snapshot` and screendump — desktop appears
   with no ScanDisk / wizard / crash.

Helper used for headless driving: `image/qmp-drive.py` (screendump / sendkey /
keyseq / mouse / powerdown / wait-shutdown).

## Publishing

The sealed qcow2 lives at `containers/win98-loco-golden-safe512.qcow2`
(gitignored — pull it from GHCR once published). Use the push script:

```bash
# GHCR needs a CLASSIC PAT with write:packages (see the token note below).
export GHCR_TOKEN=ghp_xxx
scripts/push-golden-image.sh --multi-arch     # amd64+arm64 for Android
#   pwsh scripts/push-golden-image.ps1 -MultiArch   # (Windows)
```
It builds two carriers from the one payload and pushes them:
- `win98-loco-golden:safe512-v1` (Android, builtin path)
- `emulator-snapshot:{hostgame,joingame,clean-safe512}` (cluster, qcow2 at root)

Or run the `publish-golden-image` GitHub workflow (uses the runner's
`GITHUB_TOKEN`, which has `packages: write`).

### Token note — `write:packages`
The `gho_` OAuth token in Git Credential Manager (scopes `gist, repo, workflow`)
**cannot push to GHCR and cannot be scope-extended** — OAuth-app tokens have a
fixed scope set. Create a **classic Personal Access Token** instead:
GitHub → Settings → Developer settings → Personal access tokens (classic) →
Generate new token → check **`write:packages`** (and `read:packages`, `repo`).
Use it as `GHCR_TOKEN` (or `docker login ghcr.io -u MRoie` and paste it).
