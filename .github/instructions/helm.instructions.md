---
description: "Use when editing Helm chart values, templates, or Kubernetes deployment configs. Covers Helm conventions, K8s labels, resource limits, and service configuration."
applyTo: "helm/**"
---
# Helm Chart Guidelines

## Chart Structure
- `helm/loco-chart/values.yaml` — default values
- `helm/loco-chart/templates/` — K8s manifest templates
- Override with `-f custom-values.yaml` or `--set key=value`

## Labels
- `app.kubernetes.io/name: lego-loco-cluster`
- `app.kubernetes.io/component: emulator` (for QEMU pods)
- `app.kubernetes.io/component: backend` (for backend)
- `app.kubernetes.io/component: frontend` (for frontend)

## Conventions
- Use `.Values` for all configurable parameters
- Default to 9 replicas for emulator
- Resource requests/limits: specify for all pods
- Health checks: configure liveness, readiness, startup probes
- Ports: VNC 5900-5908, WebRTC 8080-8088, backend 3000, frontend 80

## Network
- Game ports: TCP/UDP 2300, 47624 — must be allowed by NetworkPolicy
- Bridge: loco-br 192.168.10.0/24
- Pod security: NET_ADMIN capability for TAP interfaces

## Knowledge
- Document in `docs/knowledge/k8s-infra/`
