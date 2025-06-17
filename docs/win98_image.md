# Building the Windows 98 + Lego Loco Disk Image

This guide explains how to create a disk image that boots Windows 98 with Lego Loco pre-installed. The resulting image can be used by the emulator containers in this repository.

## Prerequisites

- A working PCem setup on another machine
- Windows 98 installation ISO
- Lego Loco game disc or installer
- `qemu-img` installed (part of `qemu-system-x86` or the Windows QEMU build)
- `hexdump` or `od` available for verifying the boot signature (optional)

## Steps

1. **Create a new PCem machine**
   - Configure a compatible motherboard (e.g., Intel 430VX) with 64 MB RAM.
   - Add a blank IDE hard disk around 2 GB in size.
   - Attach the Windows 98 ISO to the CD-ROM drive.

2. **Install Windows 98**
   - Boot the machine in PCem and follow the Windows setup prompts.
   - When installation finishes, shut down the guest and remove the ISO.

3. **Install Lego Loco**
   - Start the machine again and insert the Lego Loco disc or mount the installer ISO.
   - Run `SETUP.EXE` inside the guest to install the game using default options.
   - Shut down Windows once the installation completes.

4. **Export the disk image**
   - Locate the hard disk image you created in PCem (usually a `.img` file). If
     you already have a Windows 98 `.vhd` from another hypervisor you can use
     that instead.
   - Copy the disk file to your working directory on the host machine.

5. **Convert the image for container use**
  - On Linux or WSL, run the shell script below to produce `win98.img` (raw) and `win98.qcow2` (QCOW2) variants. The script verifies the disk's MBR signature (using `hexdump` or `od`) and logs progress to `create_win98_image.log` by default. It automatically uses `qemu-img` or `qemu-img.exe` depending on what is available:

   ```bash
   ./scripts/create_win98_image.sh /path/to/disk_image.img /desired/output/dir
   # .img or .vhd files are supported
   ```

  - On Windows 10 install the [QEMU for Windows](https://qemu.weilnetz.de/) binaries and run the PowerShell script. It performs the same MBR check, chooses `qemu-img` or `qemu-img.exe` automatically, and writes verbose output to `create_win98_image.log`:

   ```powershell
   .\scripts\create_win98_image.ps1 C:\path\to\disk_image.img C:\output\dir
   # Works with either .img or .vhd input
   ```

6. **Verify the QCOW2 image locally**
   - Before packaging the image, you can boot it directly with QEMU. The example
     below mirrors the container runtime flags and assumes `qemu-system-i386`
     is installed. Replace `/path/to/win98.qcow2` with your QCOW2 file and set
     `TAP_IF` to an existing TAP interface name:

   ```bash
   TAP_IF=tap0 qemu-system-i386 \
     -m 256 -hda /path/to/win98.qcow2 \
     -net nic,model=ne2k_pci -net tap,ifname=$TAP_IF,script=no,downscript=no \
     -vga cirrus -display sdl \
     -audiodev pa,id=snd0 \
     -rtc base=localtime &
   ```
   
   If the Windows 98 desktop appears the image is ready for container use.

7. **Run an emulator container**
   - Use the resulting image with the provided Dockerfiles. For example:

   ```bash
   docker run --rm --network host --cap-add=NET_ADMIN \
     -e TAP_IF=tap0 -e BRIDGE=loco-br \
     -v /path/to/win98.qcow2:/images/win98.qcow2 \
     $LOCO_REPO/qemu-loco
   ```

After completing these steps the image is ready for use in the cluster.
