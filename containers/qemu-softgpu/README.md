# Win98 SoftGPU Container

This container runs Windows 98 with SoftGPU using QEMU and exposes a noVNC interface on port 6080. A tun/tap interface is bridged to `br0` on the host for LAN play. Mount a shared volume at `/shared` for exchanging files with the VM.

## Features
- **Bochs VBE Support**: Configured with VMware VGA adapter for VESA BIOS Extensions
- **SoftGPU Compatible**: 16MB VRAM and proper VBE support for SoftGPU functionality
- **Network Gaming**: Bridged networking for LAN multiplayer games
- **Web Access**: noVNC interface for easy browser-based access

## Build
```
docker build -t youruser/win98-softgpu containers/qemu-sfotgpu
```

## Run
```
docker run --privileged -p 6080:6080 -p 2300:2300 -p 47624:47624 -v /path/to/shared:/shared youruser/win98-softgpu
```

## Port Configuration
- **6080**: noVNC web interface
- **2300**: Lego Loco multiplayer (TCP/UDP)  
- **47624**: DirectPlay/Network gaming (TCP/UDP)
- **5900**: VNC (internal, accessed via noVNC on 6080)

KEY

RC7JH-VTKHG-RVKWJ-HBC3T-FWGBG