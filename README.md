# Lego Loco Cluster

Lego Loco Cluster runs multiple instances of Lego Loco inside emulated Windows 98 environments with comprehensive health monitoring and intelligent auto-discovery.
A web dashboard streams each emulator and provides keyboard, mouse and audio control with real-time quality monitoring.
The stack uses Docker and Kubernetes so you can spin up the whole cluster with a single command.

## Features
- **Multi-Instance Gaming**: 3×3 grid of WebRTC streams for multiplayer Lego Loco
- **Audio Passthrough**: Real-time audio with level meters and quality monitoring
- **Comprehensive Health Monitoring**: Deep QEMU subsystem health probing for audio, video, and performance
- **Intelligent Auto-Discovery**: Kubernetes-based instance discovery eliminating manual configuration
- **Failure Detection & Recovery**: Automatic classification and recovery of network, QEMU, and client-side issues
- **Dockerized Windows 98**: Containerized emulator images with SoftGPU acceleration
- **Kubernetes Native**: Helm chart deployment with RBAC and service discovery
- **VR Support**: Optional VR desktop viewer on port 3002
- **Development Container**: Ready-to-use dev environment with VS Code integration

## Advanced Monitoring Features

### Deep Health Probing
The system monitors actual QEMU subsystem health beyond basic connectivity:
- **Video Subsystem**: VNC availability, X display activity, frame generation rates
- **Audio Subsystem**: PulseAudio status, device availability, signal levels
- **Performance Metrics**: CPU/memory usage, system load, resource utilization
- **Network Health**: Bridge/TAP interface status with error tracking

### Intelligent Recovery
Automatic failure classification and targeted recovery:
- **Network Issues**: Interface resets, bridge/TAP reconfiguration
- **QEMU Problems**: Process restarts, audio/video subsystem resets
- **Mixed Failures**: Sequential recovery strategies
- **Recovery Limits**: Max 3 attempts per instance with manual override

### Kubernetes Auto-Discovery
Revolutionary instance management:
- **Dynamic Discovery**: Automatically finds emulator pods from StatefulSets
- **Real-time Updates**: Watches for pod changes and updates instantly
- **RBAC Integration**: Proper service account permissions for cluster API access
- **Intelligent Fallback**: Uses static instances.json when Kubernetes unavailable

## Repository Layout
- `backend/` – signaling and API server
- `frontend/` – React dashboard
- `containers/` – emulator Dockerfiles
- `compose/` – Docker Compose configurations
- `helm/` – Helm chart
- `k8s/` – manifests and kind config
- `k8s-tests/` – cluster tests
- `scripts/` – helper utilities
- `tests/` – assorted test configs
- `docs/` – documentation

## Documentation

We have comprehensive documentation to help you understand and contribute to the project:

- **[Architecture Overview](docs/ARCHITECTURE.md)**: Detailed explanation of the system design, components, and data flows.
- **[Contributors Guide](docs/CONTRIBUTING.md)**: Instructions for setting up the dev environment and contributing code (for both humans and agents).
- **[Logging Guide](docs/LOGGING.md)**: Comprehensive guide to the logging system.
- **[Monitoring Guide](docs/MONITORING.md)**: Details on the health monitoring and metrics system.
- **[Future Tasks](docs/FUTURE_TASKS.md)**: High-level roadmap and remaining goals.

## Quick Setup
Install system packages and Node dependencies:

```bash
sudo apt-get update
sudo apt-get install -y nodejs npm qemu-system-x86 qemu-kvm wine gstreamer1.0-tools pulseaudio docker.io tcpdump
cd backend && npm install && cd ..
cd frontend && npm install && cd ..
```

Start the development stack with:

```bash
./scripts/dev-start.sh
```


## API Endpoints

### Health Monitoring
```bash
# Get comprehensive health status for all instances
GET /api/quality/deep-health

# Get health status for specific instance
GET /api/quality/deep-health/:instanceId

# Trigger recovery for failed instance
POST /api/quality/recover/:instanceId

# Get recovery status and history
GET /api/quality/recovery-status
```

### Instance Auto-Discovery
```bash
# Get discovery configuration and status
GET /api/instances/discovery-info

# Force refresh of instance discovery
POST /api/instances/refresh

# Get discovered instances
GET /api/instances
```

### Example Health Response
```json
{
  "instanceId": "instance-0",
  "overallStatus": "healthy",
  "deepHealth": {
    "qemu_healthy": true,
    "video": {
      "vnc_available": true,
      "display_active": true,
      "estimated_frame_rate": 30
    },
    "audio": {
      "pulse_running": true,
      "audio_devices": 2,
      "estimated_level": 0.7
    },
    "performance": {
      "qemu_cpu": 15.8,
      "qemu_memory": 12.4,
      "load_average": 1.2
    },
    "network": {
      "bridge_up": true,
      "tap_up": true,
      "tx_errors": 0,
      "rx_errors": 0
    }
  },
  "failureType": "none",
  "recoveryNeeded": false,
  "kubernetes": {
    "namespace": "loco",
    "podName": "loco-emulator-0",
    "discoveredAt": "2025-01-08T20:15:30Z"
  }
}
```

## Deployment

### Kubernetes with Auto-Discovery
```bash
# Deploy with auto-discovery enabled
helm install loco ./helm/loco-chart \
  --set replicas=3 \
  --set rbac.create=true \
  --set emulator.image=ghcr.io/mroie/qemu-softgpu \
  --namespace loco --create-namespace

# Verify auto-discovery is working
kubectl logs -n loco deployment/loco-backend | grep "Auto-discovered"
```

### RBAC Requirements
For auto-discovery to work, the backend needs these permissions:
```yaml
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["statefulsets"]
  verbs: ["get", "list", "watch"]
```

## Development

### Container Health Testing
Test QEMU health monitoring directly:
```bash
# Test health endpoints in container
docker exec -it <qemu-container> /health-monitor.sh test

# Get health report
docker exec -it <qemu-container> /health-monitor.sh report
```

### Integration Testing
Run comprehensive monitoring tests:
```bash
# Test monitoring integration with cluster
./scripts/test_monitoring_integration.sh

# Test with specific namespace
NAMESPACE=test-loco ./scripts/test_monitoring_integration.sh
```

Game assets are synchronized through a watcher. Each emulator pod mounts an NFS
share and `containers/qemu/watch_art_res.sh` automatically commits changes in
`<nfs>/<pod>/art/res` back to Git.

```bash
./scripts/decompress_loco_file.sh http://lan-host/file.dat
```

### Scaling Instances

The helper script `scripts/deploy_single.sh` deploys the cluster via Helm. Set
the `REPLICAS` environment variable to run `1`, `3` or `9` emulator pods:

```bash
REPLICAS=1 ./scripts/deploy_single.sh   # single instance
REPLICAS=3 ./scripts/deploy_single.sh   # three instances
REPLICAS=9 ./scripts/deploy_single.sh   # full grid
```

A future goal is to minimize resource usage by focusing on a configurable list
of active containers. See `docs/ACTIVE_STATE_PLAN.md` for details. The helper
script `scripts/set_active.sh` updates the active instance list and notifies all
connected clients. For hardware control an EV3 brick can run
`scripts/ev3_focus_ws.py` to cycle and select the focused instance using the
arrow and center buttons.
When run locally the script also uses Docker to throttle unfocused emulator
containers so the active ones receive the most CPU time.
For Kubernetes deployments, CPU requests and limits can be configured via the
`emulator.resources` section in `helm/loco-chart/values.yaml` and adjusted
dynamically with `scripts/set_active.sh`.
The VR scene now includes spatial audio so each emulator can be heard in
3D space. Instances in the active list play at full volume while others are
dimmed, with a per-instance volume slider available in VR.

Audio behaviour is controlled by `config/qemu.json`. Spatial audio and
translation quality settings can be tweaked there to ensure the QEMU pipeline
produces high quality output across all stacks.

### Codec Benchmark

Run the basic benchmark harness to deploy the cluster at 1, 3 and 9 replicas and
capture placeholder metrics:

```bash
python3 benchmark/bench.py
```
Results will be stored in `results.csv`.

### VR Desktop Viewer

After the stack is running, a separate `vr-frontend` container serves the VR
dashboard on port `3002`. Open `http://localhost:3002` in a WebXR compatible
browser or headset to view all nine instances in VR.
See `docs/VR_STREAMING_PLAN.md` for the full blueprint.
