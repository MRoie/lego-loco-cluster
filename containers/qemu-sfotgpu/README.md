# Win98 SoftGPU Container

This container runs Windows 98 with SoftGPU using QEMU and exposes a noVNC interface on port 6080. A tun/tap interface is bridged to `br0` on the host for LAN play. Mount a shared volume at `/shared` for exchanging files with the VM.

## Build
```
docker build -t youruser/win98-softgpu containers/qemu-sfotgpu
```

## Run
```
docker run --privileged -p 6080:6080 -v /path/to/shared:/shared youruser/win98-softgpu
```
