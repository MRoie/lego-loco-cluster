# Future Codex Agent Tasks for Loco LAN

This document lists all remaining work required to accept a Windows 98 image and run the cluster reliably. Each numbered section contains a **prompt** you can copy directly into a future Codex session. Follow the steps in order.

## 0. Onboarding and Setup
**Prompt:**
> "Prepare the development environment for Loco LAN on a fresh Ubuntu machine. Install all required packages and initialize the repo."

Steps:
- Install system packages: `nodejs`, `npm`, `qemu-system-x86`, `qemu-kvm`, `wine`, `gstreamer1.0-tools`, `pulseaudio`, `docker.io`, `tcpdump`.
- Run `npm install` inside both `backend/` and `frontend/`.
- Ensure Docker and Talos are available and a cluster can be created with `talosctl cluster create`.

## 1. Image Provisioning
**Prompt:**
> "Create and document a Windows 98 disk image with Lego Loco installed. Provide scripts so containers can load the image automatically."

Tasks:
- Write step-by-step instructions for installing Windows 98 and Lego Loco in an emulator.
- Add a script that converts the install to `win98.qcow2` or `win98.img` for container use.
- Update emulator entrypoints to read an image path from an environment variable.

## 2. Persistent Storage
**Prompt:**
> "Modify the Helm chart so emulator pods mount the disk image from a PersistentVolumeClaim."

Tasks:
- Mount the image via PVC and allow configuration through `values.yaml`.
- Add a toggle for read‑only mode so multiple pods can reuse one base image.

## 3. Cluster Bootstrap Scripts
**Prompt:**
> "Add helper scripts that copy the prepared disk image into the cluster and patch the Helm release automatically."

Tasks:
- Create scripts to upload the image to a volume and update the release with the correct PVC.
- Extend `scripts/start_live_cluster.sh` to call these helpers and regenerate `config/instances.json`.

## 4. Extended Test Coverage
**Prompt:**
> "Expand k8s-tests to verify networking and emulator boot state, and integrate the scripts into CI."

Tasks:
- Enhance `k8s-tests/test-network.sh` with ARP table checks and IPv6 connectivity.
- Add `k8s-tests/test-boot.sh` that waits for each emulator to expose VNC and verifies the Windows desktop.
- Run all tests in CI so failures block merges.

## 5. UI/UX Polishing
**Prompt:**
> "Improve the frontend experience and make the streaming more resilient."

Tasks:
- Allow users to select audio output devices per instance.
- Add reconnect logic to `useWebRTC` for dropped connections.
- Show loading indicators while streams establish.

## 6. VR Interface (Optional)
**Prompt:**
> "Prototype a VR scene that displays the nine video feeds and maps controller buttons to backend hotkeys."

Tasks:
- Build a basic A‑Frame scene showing the grid on a curved surface.
- Wire VR controller events to existing backend hotkey actions.

Completing these prompts will allow the repository to accept a Windows 98 + Lego Loco image and run the full cluster with stable networking, automated tests, and a polished user interface.


image link bootable 98
https://drive.google.com/file/d/1FabhMDKwF7Uu1XXsPpAycRhWSYDXqQEH/view?usp=sharing


pcem cfg file below


gameblaster = 0
gus = 0
ssi2001 = 0
voodoo = 0
model = ga686bx
cpu_manufacturer = 0
cpu = 6
fpu = builtin
cpu_use_dynarec = 1
cpu_waitstates = 0
gfxcard = v3_3000
video_speed = 5
sndcard = sbpci128
cpu_speed = 0
disc_a = 
disc_b = 
hdd_controller = ide
mem_size = 524288
cdrom_drive = 200
cdrom_channel = 2
cdrom_path = S:\Lego\em\LOOT\LOOT\gmz\NestleBarcodemegamix01.iso
zip_channel = -1
hdc_sectors = 63
hdc_heads = 16
hdc_cylinders = 20317
hdc_fn = S:\Lego\em\pcem\H2.vhd
hdd_sectors = 0
hdd_heads = 0
hdd_cylinders = 0
hdd_fn = 
hde_sectors = 0
hde_heads = 0
hde_cylinders = 0
hde_fn = 
hdf_sectors = 0
hdf_heads = 0
hdf_cylinders = 0
hdf_fn = 
hdg_sectors = 0
hdg_heads = 0
hdg_cylinders = 0
hdg_fn = 
hdh_sectors = 0
hdh_heads = 0
hdh_cylinders = 0
hdh_fn = 
hdi_sectors = 0
hdi_heads = 0
hdi_cylinders = 0
hdi_fn = 
drive_a_type = 0
drive_b_type = 0
bpb_disable = 0
cd_speed = 72
cd_model = pcemcd
joystick_type = 0
mouse_type = 3
enable_sync = 1
netcard = rtl8029as
lpt1_device = none
vid_resize = 0
video_fullscreen_scale = 0
video_fullscreen_first = 1

[Joysticks]
joystick_0_nr = 0
joystick_1_nr = 0

[SDL2]
screenshot_format = png
screenshot_flash = 1
custom_width = 640
custom_height = 480
fullscreen = 0
fullscreen_mode = 0
scale = 1
scale_mode = 1
vsync = 0
focus_dim = 0
alternative_update_lock = 0
render_driver = auto

[GL3]
input_scale = 1.000000
input_stretch = 0
shader_refresh_rate = 0.000000

[GL3 Shaders]
shaders = 0