# Golden Image — Windows 98 Provisioning Checklist

Perform inside the running provisioning VM (VNC 127.0.0.1:5901). Do each step
fully before moving on; the goal is an image that boots clean with **no
recurring hardware wizard and no ScanDisk**.

1. Let **ScanDisk** finish (first boot after an unclean state).
2. Let all pending **Plug and Play** detection complete.
3. Install the **Plug and Play Monitor** driver when prompted.
4. Confirm **IDE controllers** are healthy in Device Manager.
5. Install the **NE2000 PCI** (Realtek RTL8029(AS)) network driver.
6. **Bind TCP/IP** to the adapter; set identity (unique computer name, workgroup).
7. Install **Sound Blaster 16** — before repairing DirectX.
8. Install/repair **DirectX**.
9. Install **SoftGPU** using the QEMU standard-VGA preset (matches `-vga std`).
10. Set **800×600, High Color (16-bit)** for the baseline benchmark.
11. Install/verify **DirectPlay**.
12. Install/verify **Lego Loco**; note the launch path.
13. Verify **save/load**.
14. Only now, install **USB support** (then enable `--enable-usb` and verify the
    absolute pointer / usb-tablet).
15. Copy `guest/LOCOBOOT.BAT` to
    `C:\WINDOWS\Start Menu\Programs\StartUp\LOCOBOOT.BAT` (serial boot sentinel).
16. Complete **three cold boots** and **three clean shutdowns** (Start → Shut Down).
17. Run **Lego Loco for ≥20 minutes** (city loads, trains animate, magnifier works).
18. Run **ScanDisk** once more; confirm no errors.
19. **Shut down cleanly**, then seal (`image/seal-golden-image.sh`).

> The two current GHCR snapshots (`emulator-snapshot:hostgame` / `:joingame`)
> boot into ScanDisk + a recurring PnP Monitor wizard — they were captured from
> a running (dirty) state, not sealed after a clean shutdown. Steps 16 and 19
> are exactly what fixes that.
