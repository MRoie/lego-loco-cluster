# Quickstart & Progressive Loading Evidence — 2026-07-06

Captured from a live 2-instance LAN deployment (`values-lan-test.yaml`) on
Docker Desktop Kubernetes, running the images built after salvage PRs
#96–#99, driven by `scripts/start-lan-game.sh`.

## Progressive loading (PR #98 / draft #74 concept)

- **progressive-loading.webm** — dashboard load recorded on a throttled
  network so both phases are visible: the LEGO-themed `AppLoadingOverlay`
  first, then the instance grid.
- **progressive-loading-overlay.png** — overlay phase: NoVNC viewers show
  "Loading VNC configuration…" while the grid frame is already painted.
- **progressive-loading-loaded.png** — settled dashboard: both LAN
  emulators reporting OK, 25 FPS, QEMU/Display/Network health, benchmark
  overlay showing "2 instances | socket LAN".

## LAN emulators network-ready

- **boot0.png / boot1.png** — both Win98 guests booting with the
  RTL8029(AS) PCI Ethernet NIC detected (the cold-boot network-ready state
  from `docs/LAN_MULTIPLAYER_AND_GHCR_RUNBOOK.md`).

## Note on the in-game step

`scripts/start-lan-game.sh --skip-game` was used for this capture. The full
in-game choreography (`lan-game-steps/*.steps`) needs the emulator image
whose guests were baked to a `mainmenu` savevm with the NIC driver
pre-installed (runbook §2.5). The local `lego-loco-emulator:lan-test-flat`
image is pre-bake — its guests boot into the NIC driver wizard — so the
step runner's `loadvm mainmenu` degrades gracefully and the script
continues from live state. Bake + push a netready snapshot to run the
in-game phase end-to-end.
