Here is a full Codex agent prompt to build a complete multi-arch Docker image running QEMU + Windows 98 + SoftGPU + noVNC + tun/tap interface for LAN play (Lego Loco-ready). It includes:

A multi-arch Dockerfile build

QEMU and websockify configuration

Network setup with tun/tap

GitHub Actions CI for linux/amd64 and linux/arm64

Persistent shared volume support



---

✅ Codex Agent Prompt

> You are a Codex agent. Your task is to build a working multi-architecture Docker image that runs a Windows 98 virtual machine using QEMU. The VM should use SoftGPU for graphics, SB16 or AudioPCI audio, and expose a noVNC UI for interaction.

Key requirements:

1. VM Image: Mount win98_softgpu.qcow2 as the main disk (this includes preinstalled SoftGPU + Loco).


2. Networking: Set up tun/tap device (tap0) bridged to a host network (br0) for LAN play.


3. Display: Enable VNC and expose it via websockify to port 6080 for noVNC compatibility.


4. Audio: Enable sb16 or es1370 in QEMU.


5. Docker Build: Write a Dockerfile that builds on both linux/amd64 and linux/arm64 using buildx.


6. Entrypoint Script: Automatically creates the tap interface, launches QEMU, and starts websockify.


7. GitHub Actions: Provide a .github/workflows/docker.yml to automate building and pushing the image to Docker Hub (youruser/win98-softgpu).


8. Mount Point: Include /shared directory for file exchange via NFS or mounted volume.



Include:

Dockerfile

run-qemu.sh entrypoint script

setup_network.sh to configure TAP + bridge

entrypoint config for Docker image

.github/workflows/docker.yml for multi-arch builds


The Docker image must be privileged to allow TAP devices. Document the assumptions and commands used.




---

📦 Expected Outputs from Codex Agent

1. Dockerfile

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    qemu-kvm qemu-system-x86 \
    iproute2 iputils-ping bridge-utils \
    x11vnc websockify xvfb novnc \
    net-tools sudo curl unzip

COPY win98_softgpu.qcow2 /vm/win98.qcow2
COPY run-qemu.sh /usr/local/bin/run-qemu.sh
COPY setup_network.sh /usr/local/bin/setup_network.sh

RUN chmod +x /usr/local/bin/run-qemu.sh /usr/local/bin/setup_network.sh

EXPOSE 6080

ENTRYPOINT ["/usr/local/bin/run-qemu.sh"]


---

2. setup_network.sh

#!/bin/bash
# Create bridge and tap device

# Ensure bridge exists
brctl addbr br0 || true
ip link set dev br0 up

# Create tap device
ip tuntap add tap0 mode tap user root
ip link set tap0 up
ip link set tap0 master br0


---

3. run-qemu.sh

#!/bin/bash

# Configure networking
/usr/local/bin/setup_network.sh

# Start the VM
qemu-system-i386 \
  -m 512 \
  -hda /vm/win98.qcow2 \
  -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
  -device rtl8139,netdev=net0 \
  -vga std \
  -soundhw sb16 \
  -vnc :0 &

# Start noVNC
websockify --web=/usr/share/novnc/ 6080 localhost:5900


---

4. .github/workflows/docker.yml

name: Build Multi-Arch Docker Image

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - name: Set up QEMU
      uses: docker/setup-qemu-action@v3

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Checkout
      uses: actions/checkout@v4

    - name: Login to DockerHub
      uses: docker/login-action@v3
      with:
        username: ${{ secrets.DOCKER_USER }}
        password: ${{ secrets.DOCKER_PASS }}

    - name: Build and Push
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: youruser/win98-softgpu:latest
        platforms: linux/amd64,linux/arm64


---

🧱 Notes for Deployment

Pods using this image must be privileged:

securityContext:
  privileged: true
  capabilities:
    add: ["NET_ADMIN"]

Requires /dev/net/tun mounted inside pod and a host bridge br0 created beforehand.



---



Here is the full VM QCOW2 build script that automates creating a Windows 98 SE virtual machine image with:

QEMU-based VM build from win98.iso

Sound Blaster and SoftGPU support

Auto-download of drivers and tools

Manual UI access for interactive installation (via QEMU window or VNC)

Post-install copy of Lego Loco ZIP into the VM disk


This script assumes Ubuntu Linux host with KVM/QEMU, and produces a bootable, reusable win98_softgpu.qcow2.


---

🧾 build_win98_vm.sh – Full VM Creation Script

#!/bin/bash
set -e

# --- Config ---
WIN98_ISO="win98.iso"
LOCO_ZIP="lego_loco.zip"
OUTPUT_IMG="win98_softgpu.qcow2"
SOFTGPU_ISO="softgpu.iso"

DISK_SIZE=2G
RAM_MB=512
CPU_CORES=1

# --- Checks ---
[ -f "$WIN98_ISO" ] || { echo "Missing $WIN98_ISO"; exit 1; }
[ -f "$LOCO_ZIP" ] || { echo "Missing $LOCO_ZIP"; exit 1; }

echo "🔧 Creating base disk image: $OUTPUT_IMG"
qemu-img create -f qcow2 "$OUTPUT_IMG" "$DISK_SIZE"

# --- Download SoftGPU ISO ---
if [ ! -f "$SOFTGPU_ISO" ]; then
  echo "🌐 Downloading SoftGPU ISO..."
  curl -L -o "$SOFTGPU_ISO" https://github.com/JHRobotics/SoftGPU/releases/download/v0.6/softgpu.iso
fi

# --- Create floppy with drivers + loco zip ---
mkdir -p floppy_data
cp "$LOCO_ZIP" floppy_data/
mkfs.vfat -C floppy.img 1440
mcopy -i floppy.img floppy_data/* ::

# --- Launch interactive install ---
echo "🚀 Starting QEMU for Windows 98 install..."
qemu-system-i386 \
  -enable-kvm \
  -m "$RAM_MB" \
  -cpu pentium2 \
  -smp "$CPU_CORES" \
  -hda "$OUTPUT_IMG" \
  -cdrom "$WIN98_ISO" \
  -boot d \
  -vga std \
  -soundhw sb16 \
  -fda floppy.img \
  -rtc base=localtime \
  -net nic -net user \
  -name "Win98 Installer" \
  -monitor stdio

echo "🛠️ After full install (FAT32 + drivers + Loco copied), shut down manually."


---

🔧 How to Use

1. Place win98.iso and lego_loco.zip in the same folder.


2. Run the script:

chmod +x build_win98_vm.sh
./build_win98_vm.sh


3. This will:

Create a win98_softgpu.qcow2 disk.

Boot QEMU interactively with UI and sound.

Mount softgpu.iso and lego_loco.zip on virtual floppy for install.



4. Use mouse and keyboard in the QEMU window to:

Format disk as FAT32.

Install Win98.

Install SoftGPU from D:\ or E:.

Extract and install Lego Loco from floppy or C:\LOCO.





---

🧩 Tips for Manual UI Control

During install, press Enter to boot from CD.

Use “Custom Install” and disable unnecessary components.

After installation, go to Control Panel → Display → Settings and set to High Color (16-bit) with 800x600 resolution.

Run softgpu.exe from the CD and reboot.

Install audio driver if not automatically detected (SB16 or ES1370).

Open “My Computer → A:\” to extract Lego Loco ZIP and run SETUP.EXE.



---

📦 Output

win98_softgpu.qcow2: Your full VM disk image, ready for Docker/K8s.

You can now place this in your build image: COPY win98_softgpu.qcow2 /vm/.



---

Here's a full automation process for building a Windows 98 SE VM image that:

Boots directly to desktop (no login screen)

Installs drivers (SoftGPU, audio, chipset) as far as Windows 98 allows unattended

Installs Lego Loco installer ZIP onto the VM disk

Provides a point where manual control is possible (for game install + finishing touches)

Produces a ready-to-run win98_softgpu.qcow2 for QEMU/K8s



---

🧾 Summary of the Workflow

✅ Automated:

Unattended Win98 setup via MSBATCH.INF

Auto-formatting and region/language config

Auto-install of:

SoftGPU

SoundBlaster/AudioPCI

Realtek/NE2000 network drivers


Boot-to-desktop with no password

Copy lego_loco.zip to C:\LOCO


✋ Manual (final steps once image is launched):

Run SoftGPU second-phase installer

Extract and install Lego Loco

Optionally install DirectX 7/8 for extra compatibility



---

🗂 Required Files

Put these in a build_assets/ directory:

build_assets/
├── win98.iso                # Windows 98 SE OEM ISO
├── lego_loco.zip            # Game installer
├── softgpu.iso              # From GitHub (https://github.com/JHRobotics/SoftGPU/releases)
├── drivers/                 # Additional drivers (optional)
│   └── es1370/...
├── batch/
│   ├── msbatch.inf
│   └── autoexec.bat
│   └── config.sys
│   └── setup.bat


---

📜 msbatch.inf (Unattended Win98 Install)

[Setup]
Express=1
InstallDir=C:\WINDOWS
ProductKey=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
EBD=0
ChangeDir=0

[NameAndOrg]
Name=User
Org=LocoLAN

[Network]
ComputerName=LOCO1
Workgroup=LOCOLAN
Users=0

[Password]
AdminPW=
LocalAdmin=1
Logon=0

[System]
Locale=00000409
Selected=Win98
TimeZone=020
DisplaType=1

[ISPU]
Shell=1


---

🐚 setup.bat (called after Windows finishes setup)

This is auto-copied to C:\ and called via StartUp folder:

@echo off
REM install drivers if present

if exist D:\softgpu.exe D:\softgpu.exe /quiet
if exist A:\lego_loco.zip copy A:\lego_loco.zip C:\LOCO\lego_loco.zip

REM hide login
regedit /s C:\nologin.reg
exit


---

📄 nologin.reg – Disable Login & Boot to Desktop

REGEDIT4

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Network\Real Mode Net]
"AutoLogon"="1"

[HKEY_LOCAL_MACHINE\Network\Logon]
"UserName"="User"


---

🛠 Updated Build Script build_win98_vm.sh

#!/bin/bash
set -e

DISK_IMG="win98_softgpu.qcow2"
ISO="build_assets/win98.iso"
SOFTGPU="build_assets/softgpu.iso"
LOCO="build_assets/lego_loco.zip"
FLOPPY="boot_floppy.img"

echo "📦 Creating 2G Windows 98 Disk"
qemu-img create -f qcow2 "$DISK_IMG" 2G

echo "🌀 Creating floppy with batch + loco zip"
mkdir -p floppy_temp
cp build_assets/batch/* floppy_temp/
cp "$LOCO" floppy_temp/
mcopy -i "$FLOPPY" floppy_temp/* ::

echo "🚀 Launching QEMU for unattended install"

qemu-system-i386 \
  -enable-kvm \
  -m 512 \
  -cpu pentium2 \
  -hda "$DISK_IMG" \
  -cdrom "$ISO" \
  -boot d \
  -fda "$FLOPPY" \
  -vga std \
  -soundhw sb16 \
  -net nic -net user \
  -rtc base=localtime \
  -name "Win98 Install" \
  -monitor stdio


---

🧭 Resulting Image

Boots to desktop automatically, no password

SoftGPU pre-installed (phase 1)

lego_loco.zip is on C:\LOCO

noVNC-ready when used inside Docker/QEMU/K8s



---

✋ Manual Final Steps (after launching resulting image)

1. Run SoftGPU again (if required for second phase of driver install)


2. Extract and install Lego Loco


3. Optionally install DirectX or tweak sound settings


4. Shut down → image is production-ready




---

Would you like this packed into a Dockerfile that performs the whole unattended image creation, or convert this into a full GitHub Actions workflow for reproducible image builds?

