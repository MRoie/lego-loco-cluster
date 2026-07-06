# PR Consolidation Results — 2026-07-05/06

Execution record for [CONSOLIDATION_PLAN.md](../CONSOLIDATION_PLAN.md). All six phases completed; every open PR in the plan's intent map was merged or replaced.

## Merged PRs (in order)

| PR | Branch | Outcome |
|----|--------|---------|
| #85 | `copilot/integrate-bpy-blender-extension` | Merged (docs-only Blender issue analysis) |
| #90 | `future-tasks-updates` | Merged after cleanup + fixes (see below) |
| #92 | `copilot/integrate-reticulum-communication` | Merged; benchmark reproduced, results file split to `reticulum_results.*` |
| #89 | `copilot/implement-3d-sound-integration` | Merged after stabilization; spatial listener bug fixed |
| #94 | `feat/structured-logging` | Merged (salvage of #91; all 11 review comments addressed) |
| #93 | `feat/interactive-softgpu-config` | Merged; VXLAN mesh + mcast-socket fallback unified |
| #91 | `integrations` | **Closed** — superseded by #94 |

## Bugs found and fixed during verification

1. **Duplicate guest MACs** (#90): every QEMU instance used the default `52:54:00:12:34:56`; duplicate MACs break ARP/DirectPlay on a shared L2. Now per-instance `52:54:00:10:00:<id>` in all network modes.
2. **k8s <1.28 incompatibility** (#90): `INSTANCE_ID` came from the `apps.kubernetes.io/pod-index` label (1.28+); now derived from the StatefulSet hostname ordinal.
3. **Split socket-mode implementations** (#90): `containers/qemu` used listen/connect while `qemu-softgpu` used multicast — mixed instances joined two different L2 buses. Unified on multicast.
4. **Health monitor** (#90): `pgrep qemu-system-i386` never matched (15-char comm truncation) so `qemu_healthy` was always false; `grep -c || echo 0` emitted invalid JSON; hardcoded `:1`/`tap0` ignored `DISPLAY_NUM`/`TAP_IF`; responses were stale by one request cycle.
5. **Frontend build broken on fresh installs** (pre-existing): `@novnc/novnc` 1.7.0 (via react-vnc's `^1.5.0` range) only exports the package root; old `lib/rfb.js` deep imports failed every clean `vite build`. Root import + pinned direct dep.
6. **VR listener faced backward** (#89): the forward vector omitted the negation when rotating (0,0,−1) by the camera quaternion, mirroring front/back and left/right audio localization. Fixed + 4 regression tests (`quaternionToListenerVectors`).
7. **Frontend tests silently required a DOM** (pre-existing): vitest ran in node env; configured jsdom, guarded `window` access in the logger, added `npm test`.

## L2 networking reconciliation (#90 vs #93)

- Kubernetes: **unicast VXLAN guest mesh** (#93's proven stack — headless-service peer discovery, per-instance MAC/IP/hostname, mini-DHCP, identity floppy). This is the configuration that produced the in-game multiplayer proof (`docs/LAN_MULTIPLAYER_AND_GHCR_RUNBOOK.md`).
- Compose / no pod identity: entrypoint falls back to **#90's multicast socket LAN** when `NETWORK_MODE=socket`; the TAP NIC moves to `52:54:00:10:01:<id>` so the two NICs never collide.
- `containers/qemu` (compose emulator-0) keeps the `NETWORK_MODE` dispatcher via `setup-lan-network.sh`.

## Verification evidence

- **Shared-L2 intent test** (2 containers, socket mode): both guests boot Win98 to desktop (QMP screendumps), bidirectional Ethernet frame exchange over the multicast bus confirmed by packet capture (30/30 frames each way via `announce_self`).
- **bench.py** (`--mode direct`, 2 instances): FPS 15, latency ≤ 1.7 ms, CPU ≤ 26 %, all subsystems ✅ — all thresholds pass.
- **Reticulum benchmark** (final main): all 5 suites, 0 % loss, RTT ≈ 0.08 ms, ~13k pps → ✅ FEASIBLE. `k8s-tests/test-reticulum.sh` green against a live cluster.
- **Spatial audio**: recorded headless-Chromium evidence on branch [`evidence/spatial-audio-2026-07-06`](https://github.com/MRoie/lego-loco-cluster/tree/evidence/spatial-audio-2026-07-06/evidence) (webm + 3 frames), linked from PR #89.
- **Final main suite results**: frontend **36/36** tests + production build green; backend jest **50 passed / 9 failed** (pre-consolidation main: 5 passed / 14 failed; remaining failures are pre-existing infra-dependent suites); `helm lint`/`template` green (default + dd-single values); all container shell scripts `bash -n` clean.

## Deferred / follow-ups

- Issue #84 (Blender): close as not-planned per the analysis merged in #85 (blocked on repo permissions this session).
- ~36 stale `codex/*` remote branches listed for deletion (see plan Phase 0.3).
- Pre-existing backend test failures (infra-dependent suites: kubernetesDiscovery watch, vnc-connection, streamQualityMonitor timers) predate this consolidation.
- Draft PRs #74/#77/#79/#82 predate the plan's intent map and were left open intentionally.
