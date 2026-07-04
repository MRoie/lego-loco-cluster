# Win98 Image Creation Checklist

**Date**: 2025-01-24
**Author**: @win98-lead
**Task**: W1
**Status**: finding

## Summary
Step-by-step checklist for creating a Windows 98 SE disk image for the Lego Loco Cluster.

## Prerequisites
- PCem emulator (for initial image creation)
- Windows 98 SE ISO
- SoftGPU driver package
- RTL8029AS (ne2k_pci) network driver
- SB16 audio driver (usually included in Win98)
- Lego Loco CD/ISO
- QEMU tools (`qemu-img`)

## Pipeline

### Phase 1: PCem Setup
- [ ] Configure PCem: GA686BX board, Pentium II 300MHz, 512MB RAM
- [ ] Set graphics: Voodoo 3D (will be replaced with SoftGPU later)
- [ ] Set storage: 2GB IDE hard disk
- [ ] Boot from Win98 SE ISO

### Phase 2: Windows Install
- [ ] Format C: as FAT32
- [ ] Install Windows 98 SE (typical installation)
- [ ] Complete first-boot wizard
- [ ] Reboot and verify desktop loads

### Phase 3: Driver Installation
- [ ] Install SoftGPU (VMware VGA compatible)
  - Verify: Device Manager → Display adapters → VMware SVGA
  - Verify: Display settings → 1024×768 @ 16-bit color
- [ ] Install RTL8029AS network driver
  - Verify: Device Manager → Network adapters → RTL8029AS
  - Verify: `winipcfg` shows network adapter with IP
- [ ] Verify SB16 audio (usually auto-detected)
  - Verify: Device Manager → Sound → Creative SB16
  - Verify: Play a WAV file from Windows\Media\

### Phase 4: Game Installation
- [ ] Insert Lego Loco CD/ISO
- [ ] Run setup (autorun or D:\setup.exe)
- [ ] Accept defaults, install to C:\Program Files\LEGO Media\LEGO Loco
- [ ] Create desktop shortcut if not auto-created
- [ ] Launch game to verify it starts

### Phase 5: Export
- [ ] Shut down Windows cleanly (Start → Shut Down)
- [ ] Export VHD from PCem
- [ ] Convert: `qemu-img convert -f vpc -O qcow2 disk.vhd disk.qcow2`

### Phase 6: QEMU Verification
- [ ] Boot in QEMU with target flags:
  ```
  qemu-system-i386 -m 512 -hda disk.qcow2 \
    -device ne2k_pci,netdev=net0 -netdev tap,id=net0 \
    -device sb16 -display vnc=:0
  ```
- [ ] Verify all drivers in Device Manager
- [ ] Verify VNC displays at 1024×768
- [ ] Verify network adapter has IP
- [ ] Launch Lego Loco and verify game starts

## Known Gotchas
- SoftGPU may require VESA VBE as fallback if VMware VGA fails
- PCem VHD format is "vpc" for qemu-img (not "vhd")
- Win98 needs FAT32 not NTFS
- Some driver installs require multiple reboots
- Lego Loco autorun may not trigger — run setup.exe manually
