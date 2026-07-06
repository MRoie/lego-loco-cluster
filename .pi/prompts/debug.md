# Debug

Structured debugging workflow for the Lego Loco Cluster.

## Procedure
1. **Identify**: What's broken? (QEMU startup, discovery, streaming, VR, LAN)
2. **Knowledge check**: Search `docs/knowledge/` for prior findings on this issue
3. **Isolate**: Determine which layer is affected:
   - Emulation: `qemu_healthy` status, VNC port responsive
   - Backend: `/health` endpoint, `/api/instances` response
   - Streaming: WebRTC connection state, GStreamer pipeline
   - Frontend: Browser console errors, React component state
   - Network: Port reachability, bridge/TAP status
4. **Diagnose**: 
   - Logs: `kubectl logs <pod>` or `docker logs <container>`
   - Health: `curl http://localhost:3000/api/deep-health`
   - Probe: `node debug_probe.js`
   - Network: `k8s-tests/test-network.sh`
5. **Fix**: Apply targeted fix in the correct layer
6. **Verify**: Run relevant test suite
7. **Document**: Write findings to `docs/knowledge/<domain>/<date>-<topic>.md`

## Common Issues
| Symptom | Check | Domain |
|---------|-------|--------|
| Instance not discovered | K8s labels, RBAC | k8s-infra |
| QEMU won't start | Disk image path, KVM/TCG | emulation |
| No video in browser | VNC port, GStreamer | stream-quality |
| LAN game not found | Port 2300, broadcast | lan-networking |
| VR scene black | WebRTC track, A-Frame | vr-webxr |
