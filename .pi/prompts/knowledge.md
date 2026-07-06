# Knowledge

Write a knowledge base entry after completing work.

## Procedure
1. Determine the correct domain directory in `docs/knowledge/`:
   - vr-webxr, k8s-infra, stream-quality, frontend, backend
   - sre-monitoring, qa-testing, emulation, design
   - win98-image, lan-networking, cross-team
2. Create file: `docs/knowledge/<domain>/<date>-<topic>.md`
3. Use the standard format:

```markdown
# <Title>

**Date**: YYYY-MM-DD
**Author**: @<agent-name>
**Task**: <Task ID>
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

4. If your finding affects other domains, add an entry to `docs/knowledge/cross-team/`
5. If resolving a blocker, update the blocker status in the original entry
6. For LAN blockers, also update `docs/knowledge/lan-networking/lan-blockers-tracker.md`
