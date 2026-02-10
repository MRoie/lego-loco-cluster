# Lego Loco Cluster — Performance Benchmark Report

**Generated**: 2026-02-10T21:18:29.519799Z

## 3 Replica(s)

| Instance | Status | Avg FPS | Latency ms | CPU % | Mem % | QEMU | Display | Net |
|----------|--------|---------|------------|-------|-------|------|---------|-----|
| direct-loco-loco-emulator-0.loco-loco-emulator.loco.svc.cluster.local | healthy | 25 | 201.7 | 9.9 | 3.2% | ✅ | ✅ | ✅ |
| direct-loco-loco-emulator-1.loco-loco-emulator.loco.svc.cluster.local | healthy | 25 | 201.0 | 10.5 | 3.2% | ✅ | ✅ | ✅ |
| direct-loco-loco-emulator-2.loco-loco-emulator.loco.svc.cluster.local | healthy | 25 | 223.4 | 10.6 | 3.2% | ✅ | ✅ | ✅ |

## Pass / Fail Criteria
| Metric | Threshold | Status |
|--------|-----------|--------|
| Min FPS >= 15 | 15 | ✅ |
| Max Latency <= 250ms | 250 | ✅ |
| Max CPU <= 80% | 80 | ✅ |
