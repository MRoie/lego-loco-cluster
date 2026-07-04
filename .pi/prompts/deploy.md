# Deploy

Execute a rigorous deployment of the Lego Loco Cluster with all safety checks.

## Procedure
1. Run `cd backend && npm test` — verify all tests pass
2. Build frontend: `cd frontend && npm run build`
3. Build containers: `docker compose -f compose/docker-compose.yml build`
4. Check Kubernetes cluster: `kubectl get nodes`
5. Deploy with Helm: `helm upgrade --install loco-cluster helm/loco-chart/ -f helm/loco-chart/values.yaml`
6. Wait for pods: `kubectl rollout status deployment/loco-backend`
7. Verify health: `curl http://localhost:3000/health`
8. Verify discovery: `curl http://localhost:3000/api/instances` — expect 9 instances
9. Write deployment result to `docs/knowledge/k8s-infra/`

## Rollback
If health check fails:
```bash
helm rollback loco-cluster
```
