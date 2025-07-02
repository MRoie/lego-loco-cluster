# VR KVM Video Controls

This document summarizes hardware and software considerations for running the Windows 98 cluster with a VR interface. The stack is cloud-native and designed for CPU-only virtualization, so the guidelines below focus on keeping latency low without relying on GPU passthrough. The goal is to achieve at least 90&nbsp;fps (ideally 120&nbsp;Hz) with minimal input or audio latency.

## Hardware Recommendations

- **HDMI 2.1 / DisplayPort 1.4 KVM Switch** – Use a modern KVM that advertises 4K&nbsp;120&nbsp;Hz support. Products from AV Access, EZCOO and similar vendors provide 120&nbsp;Hz pass‑through and USB switching. When choosing a switch ensure it supports the refresh rate for both monitors and VR headsets.
- **CPU Virtualization** – The project targets CPU-only environments. Ensure the host supports hardware virtualization (Intel VT-x/AMD-V) and allocate sufficient vCPUs for each Windows&nbsp;98 instance. SoftGPU provides the display output without requiring a physical GPU.
- **Network Switching** – When hosting in the cloud, use virtio-net or other paravirtualized NICs and place the KVM switch close to the host to minimize packet latency during WebRTC streaming.
- **USB Input** – Low‑latency VR controllers require direct USB passthrough or a USB 3.0 KVM with high polling rates. Avoid hubs that throttle USB bandwidth.

## Software Notes

- Run the emulators using `qemu-system-x86_64` with the `-enable-kvm` flag.
- SoftGPU is used for rendering, so no host GPU is required. Install the SoftGPU drivers in the snapshot or container image.
- Use a display server that can present at 90&nbsp;fps or higher. Wayland or X11 with a compositor that supports the required refresh rate is recommended.
- For audio, pipe PulseAudio through the KVM switch or use network audio streaming with low‑latency codecs (Opus at 48&nbsp;kHz).

## Benchmark Script

The repository includes a helper script `scripts/benchmark_vr.sh` which measures the average frame rate of an emulator stream.

```bash
./scripts/benchmark_vr.sh http://localhost:6090/stream
```

The script records a short sample using `ffmpeg` and prints the measured FPS. It requires `ffmpeg` to be installed.
To automate latency tracking in CI or local testing, add a Makefile target:

```bash
make vr-benchmark STREAM_URL=http://localhost:6090/stream
```

This target runs the script with the given stream URL and stores logs under `benchmark_logs/`.

To benchmark the cluster at different sizes, run `scripts/benchmark_cluster.sh`.
It automatically starts the environment with 1, 3 and 9 containers, measures the
FPS for each emulator and saves a summary to a timestamped directory.

```bash
./scripts/benchmark_cluster.sh
```

