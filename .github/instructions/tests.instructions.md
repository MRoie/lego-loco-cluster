---
description: "Use when writing or editing tests: Playwright E2E, Jest unit, K8s network tests, or health monitor tests. Covers test patterns, CI conventions, and test-to-requirement traceability."
applyTo: ["tests/**", "k8s-tests/**", "backend/tests/**"]
---
# Testing Guidelines

## Test Pyramid
1. **Unit** (Jest): `backend/tests/` — service-level tests
2. **Integration** (Jest): `backend/tests/` — multi-service flows
3. **E2E** (Playwright): `tests/` — full browser tests
4. **K8s Network**: `k8s-tests/` — inter-pod connectivity
5. **VR**: WebXR device API polyfill tests

## Conventions
- Describe blocks mirror file/function structure
- Test names: "should [expected behavior] when [condition]"
- Use data-testid for Playwright selectors
- Tag tests with task IDs: `// Task: Q1`, `// Task: V2`
- Flaky tests: add `@flaky` tag with documented root cause

## K8s Network Tests
- `test-network.sh` — basic pod connectivity
- `test-tcp.sh` — TCP port reachability (2300, 47624)
- `test-broadcast.sh` — broadcast packet delivery
- `test-websocket.sh` — WebSocket connection tests

## CI (GitHub Actions with KIND)
- Cluster spinup: ~2-3 minutes
- Target: 95%+ success rate
- Run: `make test` or `cd backend && npm test`

## Knowledge
- Document test findings in `docs/knowledge/qa-testing/`
- Track flaky test roots and CI timing data
