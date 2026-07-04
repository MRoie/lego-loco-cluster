# Knowledge System

The Lego Loco Cluster project uses a shared knowledge base where every agent team documents findings, decisions, blockers, and learnings.

## Structure

```
docs/knowledge/
├── README.md              (this file)
├── vr-webxr/              VR/WebXR Lead — spatial audio, A-Frame, media export
├── k8s-infra/             Infrastructure Lead — Kubernetes, Helm, service discovery
├── stream-quality/        Stream Quality Lead — WebRTC, VNC, codecs
├── frontend/              Frontend Lead — React, Vite, Tailwind, dashboard
├── backend/               Backend Lead — Express, WebSocket, services
├── sre-monitoring/        SRE/Monitoring Lead — Prometheus, health, recovery
├── qa-testing/            QA/Testing Lead — Playwright, Jest, E2E
├── emulation/             Emulation Lead — QEMU, SoftGPU, PulseAudio
├── design/                Design Lead — Lego design system, UI/UX
├── win98-image/           Win98 Computer Use Lead — image building, drivers, navigation
├── lan-networking/        LAN Manager Lead — TAP/bridge, multiplayer, ports
└── cross-team/            Shared discoveries affecting multiple domains
```

## Knowledge Protocol

After completing any task, every agent MUST:

1. **Write findings** to `docs/knowledge/<domain>/<date>-<topic>.md`
2. **Include**: what worked, what failed, edge cases found, config values that matter
3. **Check prior art** in `docs/knowledge/cross-team/` before starting
4. **Cross-reference**: if your finding affects another domain, add an entry to `cross-team/`

## Entry Format

```markdown
# <Title>

**Date**: YYYY-MM-DD
**Author**: @<agent-name>
**Task**: <Task ID, e.g., W1, L3, K2>
**Status**: finding | decision | blocker | resolved

## Summary
Brief description of what was learned.

## Details
Full explanation with code snippets, config values, command outputs.

## Impact
Which other teams/domains this affects and why.

## References
Links to relevant files, docs, or external resources.
```

## Discovery

- Before starting work, scan your domain's knowledge directory
- Search `cross-team/` for entries tagged with your domain
- When in doubt, check `lan-networking/` and `emulation/` — they have the most cross-cutting concerns
