#!/bin/bash
set -e
echo "Setting up network for interactive mode..."
/usr/local/bin/setup_network.sh || echo "Network setup failed, but continuing..."

TAP_IF=${TAP_IF:-tap0}
if ! ip link show $TAP_IF > /dev/null 2>&1; then
    ip tuntap add dev $TAP_IF mode tap
    ip link set dev $TAP_IF up
fi

echo "Starting QEMU with direct access to /vm/win98.qcow2 (CHANGES WILL BE SAVED)..."
qemu-system-i386 \
  -M pc -cpu pentium2 -m 1024 \
  -hda /vm/win98.qcow2 \
  -drive file=/vm/softgpu.iso,media=cdrom \
  -device sb16 \
  -usb -device usb-tablet \
  -vga vmware -display vnc=0.0.0.0:0 \
  -monitor tcp:127.0.0.1:4444,server,nowait &

echo "Starting noVNC on port 6080..."
if command -v websockify >/dev/null 2>&1; then
    websockify --web=/usr/share/novnc/ 6080 localhost:5900
else
    echo "websockify not found, connect directly to VNC on port 5900."
    wait
fi

wait
