# Lego Loco Cluster — Team Directory

## Agent Team Roster

| # | Lead | pi.dev Skill | VS Code Agent | Knowledge Dir | Priority Tasks |
|---|------|-------------|---------------|---------------|----------------|
| 1 | VR/WebXR Lead | `/skill:vr-webxr` | `@vr-lead` | `docs/knowledge/vr-webxr/` | V1, V2, V3 |
| 2 | Infrastructure Lead | `/skill:k8s-infra` | `@k8s-lead` | `docs/knowledge/k8s-infra/` | **K1** (P0), K2, K3, K4, K5 |
| 3 | Stream Quality Lead | `/skill:stream-quality` | `@stream-lead` | `docs/knowledge/stream-quality/` | S1, S2, S3 |
| 4 | Frontend Lead | `/skill:frontend-react` | `@frontend-lead` | `docs/knowledge/frontend/` | F1, F2, F3 |
| 5 | Backend Lead | `/skill:backend-express` | `@backend-lead` | `docs/knowledge/backend/` | **B1** (P0), B2, B3 |
| 6 | SRE/Monitoring Lead | `/skill:sre-monitoring` | `@sre-lead` | `docs/knowledge/sre-monitoring/` | R1, R2, R3 |
| 7 | QA/Testing Lead | `/skill:qa-testing` | `@qa-lead` | `docs/knowledge/qa-testing/` | Q1, Q2, Q3, Q4 |
| 8 | Emulation Lead | `/skill:qemu-emulation` | `@emulation-lead` | `docs/knowledge/emulation/` | **E1** (P0), E2, E3, E4 |
| 9 | Design Lead | `/skill:lego-design` | `@design-lead` | `docs/knowledge/design/` | D1, D2, D3 |
| 10 | Win98 Computer Use Lead | `/skill:win98-computer-use` | `@win98-lead` | `docs/knowledge/win98-image/` | **W1** (P0), **W2** (P0), W3-W6 |
| 11 | LAN Manager Lead | `/skill:lan-manager` | `@lan-lead` | `docs/knowledge/lan-networking/` | **L1** (P0), **L2** (P0), **L3** (P0), L4-L7 |

---

## Task Assignments

### P0 — Blockers (Start Immediately)

| ID | Task | Owner | Acceptance Criteria | Depends |
|----|------|-------|-------------------|---------|
| E1 | Fix QEMU startup | @emulation-lead | `qemu_healthy: true` in health endpoint | — |
| K1 | Fix namespace discovery | @k8s-lead | Backend discovers instances without null namespace error | — |
| B1 | Fix service label matching | @backend-lead | Backend uses `app.kubernetes.io/component: emulator` | — |
| W1 | Document image creation workflow | @win98-lead | Step-by-step in knowledge base with full pipeline | — |
| W2 | Driver verification script | @win98-lead | `scripts/verify-win98-drivers.sh` checks all drivers | — |
| L1 | Create LAN blocker tracker | @lan-lead | Living doc in knowledge base with all 7 blockers | — |
| L2 | Per-instance network identity | @lan-lead | Spec for unique IP/hostname/computer-name per instance | — |
| L3 | Port 2300 reachability | @lan-lead | Test verifies TCP/UDP 2300 + 47624 between pods | K2 |

### P1 — Core Features

| ID | Task | Owner | Acceptance Criteria | Depends |
|----|------|-------|-------------------|---------|
| K2 | 9-replica scaling | @k8s-lead | All 9 pods running and discoverable | K1 |
| K3 | NetworkPolicy game ports | @k8s-lead | Ingress/egress on 2300, 47624 between emulator pods | K2 |
| K4 | Endpoints-based discovery | @k8s-lead | Endpoints API instead of pod listing | K1 |
| E2 | TAP/bridge in Kind | @emulation-lead | TAP interfaces created in Kind cluster pods | K2 |
| E3 | Audio pipeline validation | @emulation-lead | PulseAudio→GStreamer→UDP producing audio on 5001 | E1 |
| W3 | Game navigation map | @win98-lead | Full menu tree in knowledge base | — |
| W4 | Per-instance customization | @win98-lead | Script for unique hostname/IP per instance | L2 |
| W5 | Snapshot variant matrix | @win98-lead | Document all variants and known issues | — |
| L4 | Multiplayer join sequence | @lan-lead | Step-by-step flow documented | W3 |
| L5 | NetBIOS discovery test | @lan-lead | Network Neighborhood shows all instances | L2, W4 |
| L6 | Network topology diagram | @lan-lead | Bridge/TAP/pod diagram in knowledge base | — |
| V1 | Spatial audio edge cases | @vr-lead | All HRTF models, mono/3D toggle, autoplay tested | — |
| V2 | VR performance profiling | @vr-lead | 60fps benchmark with 9 streams documented | — |
| S1 | WebRTC statistics | @stream-lead | RTCStats in useWebRTC hook | E1 |
| F1 | Discovery status UI | @frontend-lead | Real-time instance discovery display | K1 |
| B2 | WebSocket reconnect | @backend-lead | Auto-reconnect on disconnect | — |
| R1 | Prometheus deployment | @sre-lead | Scraping /metrics endpoints | K2 |
| Q1 | LAN multiplayer E2E | @qa-lead | 2 instances discover + join on port 2300 | L3, E1 |
| Q2 | VR edge case tests | @qa-lead | All browsers, audio modes, export formats | V1 |
| Q3 | CI validation | @qa-lead | 95%+ CI success rate | K2 |
| D1 | Design system doc | @design-lead | Colors, typography, card states in knowledge base | — |

### P2 — Polish

| ID | Task | Owner | Acceptance Criteria | Depends |
|----|------|-------|-------------------|---------|
| K5 | Cluster setup docs | @k8s-lead | KIND/minikube comparison in knowledge base | — |
| E4 | QEMU hardware docs | @emulation-lead | Hardware reference in knowledge base | — |
| W6 | Shutdown/restart docs | @win98-lead | Procedures in knowledge base | — |
| L7 | DHCP collision prevention | @lan-lead | Unique DHCP lease per instance verified | L2 |
| V3 | Multi-format export | @vr-lead | WebM, MP4, MKV, GIF, MP3 across browsers | — |
| S2 | Adaptive streaming | @stream-lead | Auto-reduce on packet loss | S1 |
| S3 | Quality test suite | @stream-lead | Degraded network, codec, multi-load tests | S1 |
| F2 | Quality dashboard | @frontend-lead | Live metrics per instance | S1 |
| F3 | Loading optimization | @frontend-lead | <3s load, lazy-load | — |
| B3 | Rate limiting | @backend-lead | Input validation, rate limiting on writes | — |
| R2 | Grafana dashboards | @sre-lead | QEMU health, discovery dashboards | R1 |
| R3 | Alerting rules | @sre-lead | SLO violation alerts | R1 |
| Q4 | Regression suite | @qa-lead | All tests integrated | Q1-Q3 |
| D2 | Accessibility audit | @design-lead | WCAG 2.1 AA compliance | — |
| D3 | Card state specs | @design-lead | All 7 states with Lego styling | — |

---

## Task Dependency Graph (Critical Path)

```
E1 (QEMU startup) ──┐
K1 (namespace fix) ──┤
                     ├──► K2 (9 replicas) ──► L3 (port 2300) ──► Q1 (LAN E2E)
                     │                   ──► K3 (NetworkPolicy)
                     │                   ──► E2 (TAP in Kind)
B1 (labels) ─────────┘

W1-W3 (image docs) ──► W4 (unique config) ──► L5 (NetBIOS)
L1-L2 (blocker+spec) ──► L4 (join sequence) ──► Q1 (LAN E2E)
```

**Unblocked P0s** (start immediately): E1, K1, B1, W1, W2, L1, L2

---

## How to Invoke

### pi.dev
```bash
# Install pi.dev
npm install -g @mariozechner/pi-coding-agent

# Start pi in the project
pi

# Invoke skills
/skill:win98-computer-use
/skill:lan-manager
/skill:k8s-infra

# Team commands (from extension)
/team          # List all leads
/blockers      # Show known blockers
/knowledge lan-networking   # Show domain entries

# Prompt templates
/deploy        # Rigorous deployment
/test          # Full test suite
/debug         # Structured debugging
/review        # Code review
/knowledge     # Write knowledge entry
```

### VS Code Copilot
```
# In Copilot Chat, invoke agents:
@win98-lead How do I create a base Win98 image?
@lan-lead What blockers exist for multiplayer?
@k8s-lead Fix the namespace discovery issue
@design-lead Review this component for Lego styling

# Skills load automatically based on context
# Instructions apply when editing matching files
```

---

## Knowledge System

Every agent follows the **Knowledge Protocol**:

1. **Before work**: Check `docs/knowledge/<domain>/` for prior findings
2. **During work**: Note discoveries, edge cases, config values
3. **After work**: Write entry to `docs/knowledge/<domain>/<date>-<topic>.md`
4. **Cross-team**: If finding affects other domains, add to `docs/knowledge/cross-team/`
5. **Blockers**: Update `docs/knowledge/lan-networking/lan-blockers-tracker.md` for LAN issues

See [docs/knowledge/README.md](docs/knowledge/README.md) for the full knowledge system guide.

---

## Blocker Escalation

1. Agent identifies blocker during task execution
2. Write blocker entry to knowledge base with `**Status**: blocker`
3. If cross-team, add to `docs/knowledge/cross-team/`
4. Tag dependent tasks as blocked in this file
5. Resolution: update blocker to `**Status**: resolved` with solution details
