---
description: "Use when writing or editing knowledge base entries. Covers entry format, naming conventions, cross-team references, and knowledge protocol."
applyTo: "docs/knowledge/**"
---
# Knowledge Base Entry Guidelines

## File Naming
- Format: `<date>-<topic>.md` (e.g., `2025-01-15-qemu-startup-fix.md`)
- Use lowercase with hyphens
- Keep names descriptive but concise

## Entry Format
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

## Cross-Team References
- If your finding affects another domain, create an entry in `docs/knowledge/cross-team/`
- Reference the original entry: `See: ../emulation/2025-01-15-qemu-flags.md`
- Tag affected domains in the entry header

## Blocker Entries
- Use `**Status**: blocker` in header
- Include: what's blocked, who's affected, resolution path
- Update to `resolved` when fixed
- LAN blockers: always update `lan-networking/lan-blockers-tracker.md`

## Living Documents
- Some entries are living docs (updated continuously, not one-time)
- Mark with `<!-- living-document -->` comment at top
- Include revision history at bottom
