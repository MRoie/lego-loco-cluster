# LAN Multiplayer E2E Tests

**Date**: 2026-03-27  
**Author**: @qa-lead  
**Task**: Q1  
**Status**: implemented (partial — DirectPlay test stubbed)

## Summary

Added Playwright-based E2E tests that verify the LAN multiplayer infrastructure across the 9 QEMU Windows 98 instances. The tests cover instance discovery, game-port subnet validation, network identity uniqueness, and (stubbed) DirectPlay session visibility.

## Test File

`tests/lan-multiplayer.spec.js` — 4 tests in the `LAN Multiplayer — Instance Discovery` suite.

## Tests

| # | Name | Type | Status | What it verifies |
|---|------|------|--------|------------------|
| 1 | Two instances discover each other | UI + API | active | Dashboard loads, `/api/instances/live` returns ≥ 2 instances, grid renders cards |
| 2 | Game port connectivity (port 2300) | API | active | Both instances have distinct IPs on `192.168.10.0/24` game subnet |
| 3 | DirectPlay session visible | UI | **skipped** | Session name "LOCO-PARTY" appears in dashboard (requires real game automation) |
| 4 | Network identity unique per instance | API | active | Every instance has a unique IP, hostname, and MAC address |

## Dependencies

- **Backend endpoints**: `GET /api/instances/live` (primary), `GET /api/instances`
- **Frontend**: Dashboard grid with `DiscoveryStatus` component
- **Specs consumed**: `instance-identity-spec.md` (IP/hostname/MAC scheme), `multiplayer-join-sequence.md` (join flow & ports), `network-topology.md` (subnet layout)
- **Infra**: `k8s-tests/test-game-ports.sh` validates the same port 2300 / 47624 reachability at the kubectl level; this Playwright suite checks the same invariants from the dashboard/API layer.

## Running

```bash
npx playwright test tests/lan-multiplayer.spec.js
```

Requires backend on `:3001` and frontend on `:3000` (configured in `playwright.config.js` webServer entries).

## Design Decisions

1. **API-first for port and identity checks** — Playwright `request` context hits the backend directly, avoiding the need for kubectl exec or in-guest tooling.
2. **DirectPlay test skipped** — Real DirectPlay session detection needs VNC-based guest automation (key-send + OCR). Marked `test.skip` with a clear TODO.
3. **Subnet regex validation** — Rather than probing TCP 2300 from the browser (impossible), we validate that both instances sit on the `192.168.10.0/24` game subnet, which the NetworkPolicy guarantees port access for.
4. **Follows existing patterns** — Uses the same `playwright.config.js` (baseURL, webServer, retries). Test file lives in `tests/` alongside existing test scripts.

## Future Work

- Wire up VNC guest automation to un-skip the DirectPlay test
- Add a backend endpoint (`POST /api/instances/{id}/probe-port`) for real TCP probe from pod-to-pod
- Integrate into CI pipeline alongside `k8s-tests/test-game-ports.sh`
