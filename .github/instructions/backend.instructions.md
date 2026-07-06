---
description: "Use when editing backend Express server, services, WebSocket handlers, or API routes. Covers Node.js 22 patterns, service architecture, and testing conventions."
applyTo: "backend/**"
---
# Backend Development Guidelines

## Architecture
- Express server in `backend/server.js` (main) and `server-simple.js` (dev)
- Service layer in `backend/services/` — single responsibility per service
- Utilities in `backend/utils/`
- Instance states: unknown → discovered → connecting → streaming → error

## Service Patterns
- Each service exports a singleton or factory function
- Services communicate via events (EventEmitter pattern)
- Health endpoints: `/health`, `/api/instances`, `/api/deep-health`
- WebSocket for real-time instance updates

## Conventions
- Use `const` by default, `let` only when reassignment needed
- Async/await over raw Promises
- Structured logging with context (instance ID, event type)
- Error handling: try/catch at service boundaries, propagate meaningful errors

## Kubernetes Integration
- Labels: `app.kubernetes.io/component: emulator`
- Pod discovery via `kubernetesDiscovery.js`
- RBAC: ServiceAccount needs list/watch on pods

## Testing
- Run `cd backend && npm test` after changes
- Tests in `backend/tests/`

## Knowledge
- Document patterns in `docs/knowledge/backend/`
