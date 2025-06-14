# Building the Windows 98 + Lego Loco Disk Image

This guide explains how to create a disk image that boots Windows 98 with Lego Loco pre-installed. The resulting image can be used by the emulator containers in this repository.

## Prerequisites

- A working PCem setup on another machine
- Windows 98 installation ISO
- Lego Loco game disc or installer
- `qemu-img` installed (part of the `qemu-system-x86` package)

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
   - On Linux or WSL, run the shell script below to produce `win98.img` (raw) and `win98.qcow2` (QCOW2) variants. Output is logged to `create_win98_image.log` by default:

   ```bash
   ./scripts/create_win98_image.sh /path/to/disk_image.img /desired/output/dir
   # .img or .vhd files are supported
   ```

   - On Windows 10 install the [QEMU for Windows](https://qemu.weilnetz.de/) binaries and run the PowerShell script. Logging is also written to `create_win98_image.log`:

   ```powershell
   .\scripts\create_win98_image.ps1 C:\path\to\disk_image.img C:\output\dir
   # Works with either .img or .vhd input
   ```

6. **Run an emulator container**
   - Use the resulting image with the provided Dockerfiles. For example:

   ```bash
   docker run --rm --network host --cap-add=NET_ADMIN \
     -e TAP_IF=tap0 -e BRIDGE=loco-br \
     -v /path/to/win98.qcow2:/images/win98.qcow2 \
     $LOCO_REPO/qemu-loco
   ```

After completing these steps the image is ready for use in the cluster.
