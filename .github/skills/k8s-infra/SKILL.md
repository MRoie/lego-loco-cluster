---
name: k8s-infra
description: 'Kubernetes infrastructure for Lego Loco Cluster. Covers Helm chart config, KIND/minikube cluster setup, service discovery, pod scaling to 9 replicas, NetworkPolicy for game ports, and deployment workflows.'
---

# Infrastructure/K8s Skill

## When to Use
- Helm chart modifications (`helm/loco-chart/`)
- Cluster setup (KIND, minikube)
- Service discovery debugging
- Pod scaling and StatefulSet configs
- NetworkPolicy for ports 2300, 47624
- Persistent volume management

## Key Files
- `helm/loco-chart/` — Helm chart
- `kustomize/` — overlays
- `k8s/` — raw manifests
- `backend/services/kubernetesDiscovery.js` — discovery service

## Procedure
1. Check cluster state with `kubectl get pods`
2. Read `docs/knowledge/k8s-infra/` for prior findings
3. Apply changes with proper YAML validation
4. Test with `k8s-tests/` scripts
5. Document in `docs/knowledge/k8s-infra/<date>-<topic>.md`

## Tasks: K1 (namespace fix P0), K2 (9 replicas), K3 (NetworkPolicy), K4 (Endpoints), K5 (docs)
