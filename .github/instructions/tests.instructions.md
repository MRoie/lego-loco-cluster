---
description: "Use when writing or editing tests: Playwright E2E, Jest unit, Vitest unit, Python E2E, K8s network tests, SRE probes, or VNC connectivity. Covers all 74 test files, run commands, and CI conventions."
applyTo: ["tests/**", "k8s-tests/**", "backend/tests/**", "frontend/src/**/*.test.*", "scripts/test*", "benchmark/**"]
---
# Testing Guidelines

## Test Pyramid (74 files total)

| Layer | Count | Framework | Location | Run Command |
|-------|-------|-----------|----------|-------------|
| Unit (backend) | 7 | Jest 30 | `backend/tests/` | `cd backend && npm test` |
| Unit (frontend) | 4 | Vitest 4.x | `frontend/src/utils/*.test.js` | `cd frontend && npx vitest run` |
| Integration (Node) | 13 | Node.js | `tests/test-*.js` | `node tests/test-<name>.js` |
| E2E (browser) | 8 | Playwright 1.58 | `tests/*.spec.js`, `tests/playwright/` | `npx playwright test <spec>` |
| E2E (cluster) | 6 | Python 3 | `tests/e2e/` | `python tests/e2e/<name>.py` |
| K8s network | 6 | Bash | `k8s-tests/` | `bash k8s-tests/<name>.sh` |
| SRE/infra | 4 | Bash | `tests/`, `scripts/` | `bash tests/test-<name>.sh` |
| CI validation | 1 | Bash | `scripts/` | `bash scripts/ci-validate-cluster.sh` |
| Recording | 3 | Node.js | `scripts/` | `node scripts/record-<name>.js` |
| Benchmark | 1 | Python | `benchmark/` | `python benchmark/bench.py` |

## Quick Full Run
```bash
# Backend unit
cd backend && npm test && cd ..

# Frontend unit
cd frontend && npx vitest run && cd ..

# CI validation (14 checks)
bash scripts/ci-validate-cluster.sh

# K8s network (live cluster)
bash k8s-tests/test-websocket.sh
bash k8s-tests/test-game-ports.sh

# E2E Python (live cluster)
python tests/e2e/live-cluster-validation.test.py
python tests/e2e/backend_api_contract.test.py

# Playwright (needs port-forwards: 3001 backend, 3000 frontend)
npx playwright test tests/playwright/visual-proof.spec.js --project=chromium
```

## Conventions
- Describe blocks mirror file/function structure
- Test names: "should [expected behavior] when [condition]"
- Use data-testid for Playwright selectors
- Tag tests with task IDs: `// Task: Q1`, `// Task: V2`
- Flaky tests: add `@flaky` tag with documented root cause
- Python E2E tests use `kubectl exec` and `curl` — no external dependencies

## Playwright Config
- Config: `playwright.config.js` — testDir: `./tests/playwright`
- BaseURL: `http://localhost:3000` (frontend)
- Video: `retain-on-failure`, screenshot: `only-on-failure`, trace: `on-first-retry`
- Projects: chromium, firefox, webkit
- WebServer auto-starts backend:3001 + frontend:3000 (reuseExistingServer for dev)

## K8s Network Tests
- `test-websocket.sh` — WebSocket + discovery + VNC proxy validation
- `test-tcp.sh` — TCP port reachability (2300, 47624)
- `test-network.sh` — L2/L3 pod-to-pod connectivity
- `test-game-ports.sh` — DirectPlay game ports (auto-detect replicas)
- `test-broadcast.sh` — broadcast packet delivery
- `test-netbios.sh` — NetBIOS/WINS UDP 137-139

## SRE SLO Targets
- Startup success: ≥95%
- Liveness probe: ≤500ms
- Readiness probe: ≤300ms
- Probe success rate: ≥99%

## CI (GitHub Actions with KIND)
- Cluster spinup: ~2-3 minutes
- Target: 95%+ success rate
- CI script: `scripts/ci-validate-cluster.sh` (14 checks)
- Latest: 14/14 PASS

## Knowledge
- Document test findings in `docs/knowledge/qa-testing/`
- Track flaky test roots and CI timing data
