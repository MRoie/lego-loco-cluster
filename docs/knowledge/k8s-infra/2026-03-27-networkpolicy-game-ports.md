# NetworkPolicy for Game Ports

**Date**: 2026-03-27  
**Author**: @k8s-lead  
**Task**: K3 — NetworkPolicy for game ports  

## Summary

Integrated the L3-authored `k8s/networkpolicy-game-ports.yaml` into the Helm chart as a toggleable template, allowing game-port network policies to be managed via `values.yaml`.

## Ports Covered

| Port | Protocol | Purpose |
|------|----------|---------|
| 2300 | TCP/UDP | DirectPlay game traffic |
| 47624 | TCP | DirectPlay session discovery |
| 137-139 | UDP/TCP | NetBIOS name resolution |

## Design Decisions

- **Pod-to-pod only**: Both ingress and egress rules scope traffic to pods with `app.kubernetes.io/component: emulator`. No external access is granted.
- **Toggleable via values**: `networkPolicy.enabled` controls whether the resource is rendered. Defaults to `true`.
- **NetBIOS sub-toggle**: `networkPolicy.gamePorts.netbios.enabled` allows disabling NetBIOS rules independently (useful in environments where WINS/NetBIOS isn't needed).
- **Port values in values.yaml**: DirectPlay and discovery ports are configurable but default to the standard values (2300, 47624).

## Files

| File | Action |
|------|--------|
| `helm/loco-chart/templates/networkpolicy-game.yaml` | Created — Helm-templated NetworkPolicy |
| `helm/loco-chart/values.yaml` | Updated — added `networkPolicy` section |
| `k8s/networkpolicy-game-ports.yaml` | Existing — raw manifest (L3 reference) |

## Verification

```bash
# Render template locally
helm template loco helm/loco-chart/ -s templates/networkpolicy-game.yaml

# Render with policy disabled
helm template loco helm/loco-chart/ -s templates/networkpolicy-game.yaml --set networkPolicy.enabled=false
```
