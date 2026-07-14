# GHCR Snapshot Validation — hostgame / joingame

Measured 2026-07-07 against `ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:hostgame`
and `:joingame`, pulled fresh from GHCR.

## Carrier image

| Property | hostgame | joingame |
|----------|----------|----------|
| Arch / OS | linux/amd64 | linux/amd64 |
| Layers | 1 | 1 |
| Compressed size | 483 MB | 483 MB |
| Entrypoint / Cmd / Env | none (data-only carrier) | none |
| Embedded qcow2 | `/hostgame.qcow2` | `/joingame.qcow2` |
| Created | 2026-07-06T22:02Z | 2026-07-06T22:03Z |

Both are pure qcow2 data-carriers (correct pattern for a snapshot). **Single-arch
(amd64 only)** — for the Android goal these need to be republished multi-arch
(`linux/amd64,linux/arm64`); `golden-image/image/prepare-oci-context.sh` and the
`publish-golden-image` workflow do this.

## qcow2 integrity

| Property | Value (both) |
|----------|--------------|
| Format | qcow2, standalone (no backing chain) ✅ |
| Virtual size | 2 GiB |
| Disk size | 1.18 GiB |
| `qemu-img check` | No errors ✅ |
| corrupt flag | false ✅ |

## The two tags are byte-identical

```
8244945644afda556fc2d53daf481751e784c8c2aa130633b10ee25f99049c09  hostgame.qcow2
8244945644afda556fc2d53daf481751e784c8c2aa130633b10ee25f99049c09  joingame.qcow2
cmp: IDENTICAL
```

**The host vs join distinction is not baked into the disk.** Both tags carry the
same Win98 snapshot. Differentiation must therefore come from runtime config
(instance ordinal, DHCP master, and whether the guest is scripted to *create* vs
*join* the LAN game), or the images need to be re-baked from two genuinely
different in-game states.

## Boot state (read-only `-snapshot` boot, pentium3/512 MB TCG)

Timeline: ScanDisk ~60 s → Windows video-mode switch ~110 s → Lego Loco desktop ~150 s.

- **`snapshot-boot-scandisk.png`** — first frame: *"Microsoft ScanDisk — Because
  Windows was not properly shut down."* The image was captured from a dirty
  (running) state, not sealed after a clean shutdown, so **ScanDisk runs on every
  cold boot**.
- **`snapshot-boot-loco-desktop.png`** — post-boot: a 1024×768 desktop with the
  **Lego Loco city world loaded** (isometric tiles / houses / rails), but an
  *"Add New Hardware Wizard — Plug and Play Monitor"* modal on top: the guest
  **re-runs hardware detection on boot**.

## Verdict against our standard

| Acceptance criterion | Result |
|----------------------|--------|
| qcow2 valid / standalone / not corrupt | ✅ |
| Reaches a running Lego Loco desktop | ✅ (city loaded) |
| No ScanDisk after clean shutdown | ❌ boots into ScanDisk |
| No recurring hardware wizard | ❌ PnP Monitor wizard on boot |
| Host vs join differentiated | ❌ byte-identical |
| Multi-arch (amd64 + arm64) for Android | ❌ amd64 only |

**Benchmarkability**: these boot to a running-Loco desktop, but producing our
standard `bench.py` numbers (FPS ≥ 15, latency ≤ 250 ms, CPU ≤ 80 %) requires
running them *through the emulator container* (GStreamer + health endpoint), not
bare QEMU — the carriers have no entrypoint. Deploy via the emulator image with
`SNAPSHOT_TAG=hostgame` to get the standard numbers.

**Recommended fix**: re-bake per `DRIVER-INSTALL-CHECKLIST.md` steps 16–19 (three
clean shutdowns, seal only after a clean shutdown via `seal-golden-image.sh`) so
the sealed image is ScanDisk-free and wizard-free, and capture host and join from
two distinct in-game states (or drive the role at runtime and keep one golden base).
