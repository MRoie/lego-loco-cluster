# Performance Profiles

## Guest RAM

Windows 98 is unsafe above ~512 MB without a validated high-memory patch
(VCACHE / system.ini `MaxFileCache`, and often a `MaxPhysPage` limit).

| Profile | RAM | Status |
|---------|-----|--------|
| `safe512` | 512 MB | Mandatory baseline. Default everywhere. |
| `highmem1024` | 1024 MB | Only after installing a user-supplied, legally obtained Win98 memory patch; must pass staged tests at 768 MB then 1024 MB. |

The patch is **not** shipped in this repo. `highmem1024` should be treated as
experimental until validated on the target device.

## Host TCG cache

Guest RAM and the host emulation cache are independent knobs. On ARM Android the
x86 guest runs under TCG; a larger translation-block cache reduces re-translation
overhead. Default `--tcg-cache 1024` (MB). This does **not** change guest RAM and
does not require the memory patch.

## Graphics

Primary production profile:
- QEMU **standard VGA** (`-vga std`) — matches the SoftGPU standard-VGA driver.
- **Pentium III** guest CPU (`-cpu pentium3`) to expose SSE.
- **800×600 @ 16-bit** for the first benchmark; test 1024×768 / 32-bit later.

Experimental (separate overlay/image — never mixed into production):
- **Cirrus VGA** at 800×600 / 16-bit.

Do not assume VMware VGA gives accelerated 3D under standard QEMU on Android, and
do not assume more guest RAM fixes the throughput bottleneck (first-boot hardware
detection, ScanDisk, and the TCG-on-ARM translation path dominate early frames).

## Observed boot timeline (reference)

Booting the current GHCR `emulator-snapshot` qcow2 under plain TCG (pentium3,
512 MB) on a desktop host: ScanDisk ~60 s → Windows video-mode switch ~110 s →
Lego Loco desktop reachable ~150 s. Android TCG-on-ARM will be slower; measure
per device rather than assuming.
