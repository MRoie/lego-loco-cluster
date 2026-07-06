---
name: qa-testing
description: 'QA and testing for Lego Loco Cluster. Covers Playwright E2E tests, Jest unit tests, WebXR VR testing, LAN multiplayer validation, CI hybrid cluster (KIND), and test traceability.'
---

# QA/Testing Skill

## When to Use
- Writing Playwright E2E tests
- Jest unit/integration tests
- WebXR device testing
- CI pipeline validation
- LAN multiplayer E2E flows

## Key Files
- `playwright.config.js` — Playwright config
- `backend/tests/` — backend tests
- `tests/` — project tests
- `k8s-tests/` — K8s network tests

## Procedure
1. Understand existing test suites and gaps
2. Check `docs/knowledge/qa-testing/` for prior findings
3. Write tests following existing patterns
4. Verify CI stability
5. Document in `docs/knowledge/qa-testing/<date>-<topic>.md`

## Tasks: Q1 (LAN E2E), Q2 (VR edge cases), Q3 (CI validation), Q4 (regression suite)
