# Review

Code review with architecture awareness for the Lego Loco Cluster.

## Procedure
1. **Scope**: Identify which domains the changes touch
2. **Knowledge check**: Read relevant `docs/knowledge/<domain>/` for context
3. **Architecture compliance**:
   - Does it follow the service layer pattern? (backend)
   - Does it use the ActiveContext provider? (frontend)
   - Does it follow Lego design system? (UI changes)
   - Are K8s labels correct? (infrastructure)
4. **Cross-team impact**: Does this change affect other domains?
5. **Testing**: Are there tests for the changes?
6. **Security**: Input validation, no secrets in code, proper error handling
7. **Performance**: Does it maintain 60fps (VR), <3s load (frontend)?

## Checklist
- [ ] Changes match the assigned task ID
- [ ] Tests added or updated
- [ ] Knowledge base updated if new findings
- [ ] No regressions in existing tests
- [ ] Cross-team references added if applicable
- [ ] Follows conventions in `.github/instructions/`
