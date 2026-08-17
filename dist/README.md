# Released bundles

Downloadable, ready-to-install packages. Rebuild with
`bash scripts/package-android-lens.sh --out dist`.

## `loco-lens-android.{zip,tar.gz}`
Self-contained Termux bundle to run Windows 98 + Lego Loco under QEMU on an
Android phone and drive the M5Stack "Loco Lens" watch from it — no cluster.

On the phone:
```bash
# grab one (raw GitHub link works on mobile):
#   loco-lens-android.zip   or   loco-lens-android.tar.gz
unzip loco-lens-android.zip        # or: tar -xzf loco-lens-android.tar.gz
cd loco-lens-android
bash install.sh                    # Termux pkgs + node deps (incl. arm64 sharp)
# place the golden image at ~/loco-runtime/images/win98.qcow2
./run-all.sh                       # QEMU (VNC :5901) + lens server
# watch → ws://<phone-ip>:3001/ws/lens/local
```

The ~500 MB golden qcow2 is intentionally **not** bundled — pull it from GHCR
or copy it to `~/loco-runtime/images/win98.qcow2`. See
`golden-image/docs/ANDROID-LENS-TOPOLOGY.md`.

Checksums: `loco-lens-android.sha256`.
