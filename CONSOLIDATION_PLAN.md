# PR Consolidation Plan — Claude Code Session

Goal: fold all open work into one better overall product on `main`, merging each branch only after its original intent is tested and benchmarked. Generated 2026-07-05 from live analysis of the repo and GitHub state.

Baseline: `main` @ `3e21d19` (merge of #88 UDP-to-WebRTC bridge). Working machine state: "decently reliable game machine" — VNC dual implementation, storage strategy, health probes all landed in main.

---

## Intent map — what each open branch is actually for

| PR | Branch | Intent | Size | Merge state vs main |
|----|--------|--------|------|---------------------|
| #92 (draft) | `copilot/integrate-reticulum-communication` | Design docs for Reticulum mesh networking + WASM portability plan, plus a 625-line benchmark harness (5 suites, committed results) and a k8s test script. Docs/bench only — no runtime code touched. | +1,453, 8 files | fast-forward, clean |
| #91 | `integrations` | Structured logging (`backend/utils/logger.js`, 112 lines), k8s discovery RCA doc, `dev-cycle-deploy.sh` (517 lines), `simple-backend-deploy.sh`, helm deployment tweaks. | +1,156 / −133, 19 files | **20 behind main, conflicts** in backend/server*.js, services/*, helm templates/values |
| #90 | `future-tasks-updates` | Mislabeled ".gitignore fix" — actually: shared L2 networking + DirectPlay config for QEMU guests, NoVNC fullscreen, VR service + benchmark config, Launcher v3 tools (`tools/safe_launch.py`, `verify_run.py`, etc.). Contains junk output artifacts (`v2_out.txt`, `v3_out.txt`, `v3_round2.txt`). | +13,584 / −174, 108 files | fast-forward, clean |
| #89 (draft) | `copilot/implement-3d-sound-integration` | 3D spatial audio for VR (Web Audio API), performance/video recording hooks, multi-format media export (MP4/MKV/GIF/MP3/WebM), recording agent skill, benchmark recordings. Last commit is literally "more bugs" — known-unstable. | +4,283 / −143, 93 files | fast-forward, clean |
| #85 | `copilot/integrate-bpy-blender-extension` | One doc (`ISSUE_ANALYSIS.md`): concludes the Blender/bpy issue was filed in the wrong repo. Administrative, no code. | +56, 1 file | clean |
| local | `feat/interactive-softgpu-config` | LAN multiplayer bring-up: guest NIC install, Win98 CD patch, QMP step runner (wiz1–9), bake/extract pipeline, GHCR inventory, dd-single helm values, LAN_MULTIPLAYER_AND_GHCR_RUNBOOK.md. WIP committed as `ef2eba6`; **not yet pushed, no PR**. | +2,013, 135 files | needs push + PR |

### Overlaps that dictate merge order
- #92 ∩ #90: `.gitignore`, `benchmark/results.csv`, `docs/FUTURE_TASKS.md` — trivial.
- #90 ∩ #89: **10 files**, including `backend/server.js`, `containers/qemu*/entrypoint.sh`, `containers/qemu-softgpu/Dockerfile`, `frontend/src/components/InstanceCard.jsx`, `helm/loco-chart/templates/emulator-statefulset.yaml` — real collision surface. Whichever merges second must be rebased and re-tested.
- #92, #90, #89 each contain today's main, so the first merge is a fast-forward; every later one needs a rebase.
- local branch ∩ #90: both touch QEMU networking/DirectPlay territory (L2 networking in #90 vs NIC/dplay bring-up locally) — reconcile intentionally, not mechanically.

### #91 stale-side findings (examined per your instruction)
Main moved on (20 commits: VNC integration, stability fixes, UDP bridge) but **did not supersede** #91's core value:
- `backend/utils/logger.js` does not exist on main — main regressed to `console.log` with emoji. The structured logger is worth salvaging.
- Main's `kubernetesDiscovery.js` is newer and has its own namespace handling; #91's version of that file is stale — take main's, re-apply only logger wiring.
- `dev-cycle-deploy.sh` / `simple-backend-deploy.sh` don't exist on main; independent, salvageable.
- Helm template diffs in #91 are stale vs main's storage-strategy/probe work — discard, keep main.

Verdict: don't merge #91 as-is. Cherry-pick its value onto a fresh branch (Phase 4) and close #91.

---

## Session plan (phases in dependency order)

### Phase 0 — Housekeeping (10 min)
1. Push `feat/interactive-softgpu-config` (`ef2eba6`) and open its PR.
2. Merge #85 (docs-only, zero risk) and close the underlying Blender issue as not-applicable to this repo.
3. Clean up: `git remote prune origin`; list the ~30 stale `codex/*` branches for deletion after this consolidation.

### Phase 1 — #90 `future-tasks-updates` (foundation, merge first)
It's the largest and other work builds on the same files.
1. Delete junk artifacts from the branch: `v2_out.txt`, `v3_out.txt`, `v3_round2.txt`, any other captured output.
2. Test intent: shared L2 networking + DirectPlay between ≥2 QEMU guests (`tools/test_run.py`, `tools/verify_run.py`); NoVNC fullscreen manually; launcher keep-alive via `tools/safe_launch.py`.
3. Benchmark: run `benchmark/bench.py` before/after; record in PR.
4. Merge (fast-forward) once green.

### Phase 2 — #92 Reticulum (low risk, merge second)
1. Rebase on new main (only trivial overlaps: .gitignore, FUTURE_TASKS.md, results.csv).
2. Run `benchmark/reticulum_bench.py` — verify the 5 suites pass and committed results reproduce; run `k8s-tests/test-reticulum.sh` against a kind cluster.
3. Docs are design-stage: confirm they describe intended direction, mark ready, merge.

### Phase 3 — #89 3D spatial audio (highest risk, needs real stabilization)
Last commit "more bugs" means intent is NOT yet satisfied. Work the branch:
1. Rebase onto post-#90 main — resolve the 10 overlapping files (entrypoints, server.js, InstanceCard.jsx, emulator-statefulset).
2. Fix the known bugs; get spatial audio working in the VR interface with smooth listener ramps (the review fixes are already in: shared AudioContext state, dependency arrays).
3. Benchmark to satisfaction: run its recording/benchmark hooks (`scripts/record-spatial-audio.js`, `record-cluster-audio.js`); acceptance = smooth positional audio with no dropouts across a 3×3 grid, recorded evidence attached to PR.
4. Only then mark ready and merge.

### Phase 4 — #91 salvage (replace, don't merge)
1. New branch `feat/structured-logging` off main: bring over `backend/utils/logger.js`, wire into `server.js`/services (keeping main's k8s discovery logic), bring `dev-cycle-deploy.sh` + `simple-backend-deploy.sh` + the RCA doc.
2. Run backend tests (`backend/tests/`, incl. `streamQualityMonitor.test.js`).
3. PR the new branch; close #91 with a comment linking the replacement.

### Phase 5 — Local branch `feat/interactive-softgpu-config`
1. Rebase onto post-Phase-1 main; reconcile with #90's L2 networking (the branches approach QEMU networking from two ends — unify DirectPlay config).
2. Test intent: LAN multiplayer session between two instances per the runbook; verify GHCR publish scripts against the registry.
3. Merge when the multiplayer proof reproduces on the rebased branch.

### Phase 6 — Post-consolidation verification
1. Full CI run (KIND-primary hybrid strategy per CI_TASKS.md).
2. Re-run `benchmark/bench.py` + reticulum + audio benchmarks on final main; commit a consolidated results doc.
3. Update `TASKS_ORCHESTRATION.md` statuses (Task 1.1 k8s discovery is fixed on main) and prune `docs/FUTURE_TASKS.md` items delivered by this consolidation.
4. Delete merged branches; repo should end with 0 open PRs or only intentionally-open ones.

---

## Risk notes
- #90 and #89 both touch container entrypoints and the emulator statefulset — after Phase 1, #89's rebase is the riskiest step; do it file-by-file.
- #89 and #90 both add recording/VR tooling with overlapping `package.json` edits — dedupe dependencies during the Phase 3 rebase.
- Sandbox note: this environment cannot push (no GitHub credentials); Phases assume a Claude Code session with `gh` auth on the host machine.
