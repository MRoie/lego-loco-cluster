# 9-Instance Benchmark Report - Full 3x3 Grid

**Date**: 2026-02-10  
**Environment**: Kind cluster (single node, 8 CPU / 64 GB RAM)  
**Replicas**: 9 QEMU emulators (Win98, Pentium2, 512MB)  
**Resolution**: 1024x768 @ 25fps (H.264/GStreamer)  
**Network Mode**: Socket (QEMU socket networking)  
**Helm Revision**: 8 (backend:v3, frontend:v2, qemu-loco:latest)

## Summary

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Healthy Instances | **9/9 (100%)** | 9/9 | **PASS** |
| Target FPS | **25 fps** | ≥ 15 fps | **PASS** |
| Avg Latency | **343 ms** | ≤ 500 ms | **PASS** |
| Avg CPU | **31.7%** | ≤ 80% | **PASS** |
| Avg Memory | **5.9%** | ≤ 80% | **PASS** |
| QEMU Health | **9/9 healthy** | all | **PASS** |
| Display Active | **9/9 active** | all | **PASS** |
| VNC Available | **9/9 available** | all | **PASS** |
| Audio Running | **9/9 running** | all | **PASS** |
| Network Bridge | **9/9 OK** | all | **PASS** |

**OVERALL: ALL PASS** (10/10 criteria met)

## Per-Instance Metrics (Sample Average)

| Instance | Pod IP | FPS | Latency (ms) | CPU (%) | Memory (%) | QEMU | VNC | Audio |
|----------|--------|-----|-------------|---------|------------|------|-----|-------|
| instance-0 | 10.244.0.27 | 25 | 354 | 30.0 | 5.9 | OK | OK | OK |
| instance-1 | 10.244.0.26 | 25 | 328 | 32.7 | 5.9 | OK | OK | OK |
| instance-2 | 10.244.0.25 | 25 | 336 | 31.9 | 5.9 | OK | OK | OK |
| instance-3 | 10.244.0.19 | 25 | 350 | 31.4 | 5.9 | OK | OK | OK |
| instance-4 | 10.244.0.20 | 25 | 355 | 31.3 | 5.9 | OK | OK | OK |
| instance-5 | 10.244.0.21 | 25 | 328 | 33.2 | 5.9 | OK | OK | OK |
| instance-6 | 10.244.0.22 | 25 | 352 | 30.9 | 5.9 | OK | OK | OK |
| instance-7 | 10.244.0.23 | 25 | 321 | 32.8 | 5.9 | OK | OK | OK |
| instance-8 | 10.244.0.24 | 25 | 349 | 30.8 | 5.9 | OK | OK | OK |

## Time Series (5 samples, ~5s intervals)

| Sample | Time (UTC) | Healthy | Avg FPS | Avg Latency | Avg CPU | Avg Memory |
|--------|-----------|---------|---------|-------------|---------|------------|
| 1 | 22:40:07 | 9/9 | 25 | 266 ms | 26.2% | 6.0% |
| 2 | 22:40:11 | 9/9 | 25 | 353 ms | 32.7% | 6.0% |
| 3 | 22:40:12 | 9/9 | 25 | 362 ms | 33.7% | 5.9% |
| 4 | 22:40:17 | 9/9 | 25 | 467 ms | 40.4% | 5.9% |
| 5 | 22:40:17 | 9/9 | 25 | 268 ms | 25.4% | 5.9% |

## Resource Limits per Emulator

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 200m | 800m |
| Memory | 256Mi | 768Mi |

## Key Observations

1. **100% health**: All 9 emulators maintained 100% health throughout the benchmark run
2. **Stable FPS**: 25 fps consistent across all instances and all samples
3. **Latency spikes**: Sample 4 showed elevated latency (467ms avg) likely due to probe overhead when all 9 are queried simultaneously
4. **Steady-state latency**: ~266ms when system is idle (samples 1 & 5)
5. **CPU scaling**: 25-40% per instance when actively probed; 9 instances × ~30% = ~270% total (of 800% available)
6. **Memory efficient**: ~6% memory usage per instance, well within limits
7. **Socket networking**: All instances report network bridge and tap interfaces up (socket mode active)
8. **Audio/VNC**: All subsystems operational across all 9 instances

## Comparison: 3-Instance vs 9-Instance

| Metric | 3 Instances | 9 Instances | Delta |
|--------|------------|------------|-------|
| FPS | 25 | 25 | 0% |
| Avg Latency | ~210 ms | ~343 ms | +63% |
| Avg CPU | ~10% | ~32% | +220% |
| Memory | 3.2% | 5.9% | +84% |
| Health | 3/3 | 9/9 | - |

Latency and CPU increase are expected with 3x the instances on a shared 8-CPU node.
