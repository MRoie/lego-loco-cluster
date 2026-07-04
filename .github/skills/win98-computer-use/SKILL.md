---
name: win98-computer-use
description: 'Windows 98 image creation and computer use for Lego Loco Cluster. Covers PCem-to-QCOW2 pipeline, SoftGPU/RTL8029/SB16 drivers, Lego Loco game navigation, snapshot lifecycle, safe shutdown, and guest troubleshooting.'
---

# Win98 Computer Use Skill

## When to Use
- Creating or modifying Windows 98 SE disk images
- Driver installation (SoftGPU, RTL8029AS, SB16)
- Lego Loco game installation and navigation
- Snapshot creation and lifecycle
- Safe shutdown, restart, recovery
- Per-instance image customization

## Image Pipeline
PCem → Win98 SE install → Drivers → Lego Loco → VHD export → `qemu-img convert -f vpc -O qcow2` → Verify

## Driver Checklist
- SoftGPU (VMware VGA): 1024×768 @16bpp
- RTL8029AS (ne2k_pci): IP visible in winipcfg
- SB16: WAV playback
- VESA VBE: fallback

## Key Files
- `scripts/create_win98_image.sh`, `scripts/snapshot_builder.py`
- `containers/qemu-softgpu/Dockerfile`
- `docs/win98_image.md`, `docs/LESSONS_LEARNED_WIN98_ISO.md`

## Procedure
1. Review image creation scripts and docs
2. Check `docs/knowledge/win98-image/` for prior findings
3. Follow image pipeline for modifications
4. Verify drivers in Device Manager
5. Document in `docs/knowledge/win98-image/<date>-<topic>.md`

## Tasks: W1 (image workflow P0), W2 (driver verify script P0), W3 (game nav), W4 (per-instance config), W5 (snapshot matrix), W6 (shutdown/restart)
