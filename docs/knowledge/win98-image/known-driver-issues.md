# Known Driver Issues

**Date**: 2025-01-24
**Author**: @win98-lead
**Task**: W1
**Status**: finding

## Summary
Known issues and workarounds for Windows 98 SE drivers in the QEMU emulation environment.

## SoftGPU (VMware VGA)
- **Issue**: SoftGPU may not initialize on first boot after install
- **Workaround**: Reboot twice; if still failing, fall back to VESA VBE driver
- **Verification**: Device Manager → Display adapters should show "VMware SVGA II"
- **Resolution**: 1024×768 @ 16bpp is the target; 800×600 minimum with VESA fallback

## RTL8029AS (ne2k_pci)
- **Issue**: Driver may not auto-detect in Windows 98 — requires manual install
- **Workaround**: Control Panel → Add New Hardware → specify driver from floppy/CD
- **Verification**: `winipcfg` should show the adapter with an IP address
- **Note**: ne2k_pci is the QEMU model name; Windows sees it as "Realtek RTL8029(AS)"

## SB16 Audio
- **Issue**: Usually auto-detected, but DMA/IRQ conflicts possible
- **Workaround**: Verify in Device Manager no yellow exclamation marks
- **Verification**: Play C:\Windows\Media\tada.wav
- **Note**: PulseAudio on host must be running for audio pipeline to work

## VESA VBE (Fallback Display)
- **Issue**: Lower resolution than SoftGPU (800×600 max vs 1024×768)
- **When to use**: Only if SoftGPU fails completely
- **Note**: Some Lego Loco UI elements may be cut off at 800×600
