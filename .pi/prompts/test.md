# Test

Run the complete test suite for the Lego Loco Cluster.

## Procedure
1. **Unit tests**: `cd backend && npm test`
2. **Integration**: Review test results for service interaction tests
3. **E2E**: `npx playwright test` (requires running frontend + backend)
4. **K8s network**: 
   ```bash
   bash k8s-tests/test-network.sh
   bash k8s-tests/test-tcp.sh
   bash k8s-tests/test-broadcast.sh
   ```
5. **VR tests**: Run with WebXR device polyfill
6. **Health**: `node debug_probe.js`
7. Write test results to `docs/knowledge/qa-testing/`

## Quick Check
For a fast validation:
```bash
cd backend && npm test && echo "Backend OK"
cd ../frontend && npm run build && echo "Frontend OK"
```
