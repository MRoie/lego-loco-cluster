---
name: backend-express
description: 'Backend Express server for Lego Loco Cluster. Covers Node.js 22 API routes, WebSocket signaling, instance lifecycle, VNC proxy chain, service layer architecture, and health endpoints.'
---

# Backend Express Skill

## When to Use
- Express route creation or modification
- WebSocket signaling and events
- Instance lifecycle management
- VNC proxy debugging
- Service layer architecture

## Key Files
- `backend/server.js` — Express server
- `backend/services/instanceManager.js` — lifecycle
- `backend/services/kubernetesDiscovery.js` — discovery
- `backend/services/probingService.js` — probing

## Procedure
1. Understand service architecture and instance states
2. Check `docs/knowledge/backend/` for prior findings
3. Follow existing service patterns
4. Run `cd backend && npm test` after changes
5. Document in `docs/knowledge/backend/<date>-<topic>.md`

## Tasks: B1 (label fix P0), B2 (WebSocket reconnect), B3 (rate limiting)
