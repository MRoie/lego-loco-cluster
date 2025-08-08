# QEMU Health Monitoring & Auto-Discovery

This document describes the comprehensive health monitoring and intelligent auto-discovery features implemented in the Lego Loco Cluster.

## Overview

The system provides deep insight into QEMU streaming quality through:
- **Container Health Endpoints**: Detailed health metrics via HTTP on port 8080
- **Kubernetes Auto-Discovery**: Dynamic instance discovery from StatefulSet pods
- **Intelligent Failure Recovery**: Automatic classification and recovery of issues
- **Real-time Quality Monitoring**: Continuous audio, video, and performance tracking

## Architecture

### Health Monitoring Components

1. **Container Health Scripts** (`/health-monitor.sh`)
   - Exposed on port 8080 in each QEMU container
   - Monitors QEMU process, video subsystem, audio devices, performance, and network
   - Returns JSON health reports with detailed metrics

2. **Backend Quality Monitor** (`streamQualityMonitor.js`)
   - Polls container health endpoints every 15 seconds
   - Performs connectivity and functionality tests every 5 seconds
   - Classifies failures and triggers recovery mechanisms

3. **Kubernetes Discovery** (`kubernetesDiscovery.js`)
   - Auto-discovers emulator pods using label selectors
   - Watches for real-time pod changes
   - Falls back to static instances.json when K8s unavailable

### Auto-Discovery Process

1. **Service Account Setup**: Backend uses RBAC-enabled service account
2. **Pod Discovery**: Finds pods with labels `app.kubernetes.io/component=emulator`
3. **Real-time Watching**: Monitors pod lifecycle events
4. **Instance Generation**: Automatically creates instance configurations
5. **Fallback Handling**: Uses static config when discovery fails

## Health Metrics

### Video Subsystem
```json
{
  "vnc_available": true,
  "display_active": true,
  "estimated_frame_rate": 30,
  "vnc_port": 5901,
  "display": ":1"
}
```

### Audio Subsystem
```json
{
  "pulse_running": true,
  "audio_devices": 2,
  "alsa_devices": 1,
  "estimated_level": 0.7,
  "audio_backend": "pulse"
}
```

### Performance Metrics
```json
{
  "cpu_usage": 25.3,
  "memory_usage": 45.1,
  "load_average": 1.2,
  "qemu_cpu": 15.8,
  "qemu_memory": 12.4,
  "qemu_pid": "1234"
}
```

### Network Health
```json
{
  "bridge_up": true,
  "tap_up": true,
  "tx_packets": 15420,
  "rx_packets": 12893,
  "tx_errors": 0,
  "rx_errors": 0
}
```

## Failure Classification

The system automatically classifies failures into categories:

### Network Issues
- Bridge/TAP interface down
- High packet loss or errors
- Connectivity timeouts
- **Recovery**: Interface resets, bridge reconfiguration

### QEMU Issues  
- Process not responding
- VNC unavailable
- Audio subsystem failure
- High resource usage
- **Recovery**: Process restart, subsystem resets

### Client Issues
- WebRTC connection problems
- Browser-side errors
- Codec incompatibility
- **Recovery**: Stream restart, quality fallback

### Mixed Issues
- Multiple issue types detected
- **Recovery**: Sequential network then QEMU recovery

## API Reference

### Health Endpoints

#### Get Deep Health Status
```bash
GET /api/quality/deep-health
GET /api/quality/deep-health/:instanceId
```

Response includes:
- Overall health status
- Detailed subsystem metrics
- Failure type classification
- Recovery recommendations
- Kubernetes metadata

#### Trigger Recovery
```bash
POST /api/quality/recover/:instanceId
```

Initiates recovery process based on detected failure type.

#### Recovery Status
```bash
GET /api/quality/recovery-status
```

Returns recovery attempt history and current status.

### Discovery Endpoints

#### Discovery Information
```bash
GET /api/instances/discovery-info
```

Returns:
- Discovery mode (auto vs static)
- Kubernetes namespace
- Service information
- Cache status

#### Refresh Discovery
```bash
POST /api/instances/refresh
```

Forces immediate instance discovery refresh.

#### Instance List
```bash
GET /api/instances
```

Returns discovered or static instance configurations.

## Deployment Configuration

### Kubernetes Deployment
```yaml
# Required labels for auto-discovery
metadata:
  labels:
    app.kubernetes.io/component: emulator
    app.kubernetes.io/part-of: lego-loco-cluster
```

### RBAC Configuration
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["statefulsets"]
  verbs: ["get", "list", "watch"]
```

### Helm Values
```yaml
rbac:
  create: true
emulator:
  image: ghcr.io/mroie/qemu-softgpu
  tag: latest
backend:
  env:
    KUBERNETES_NAMESPACE: loco
```

## Testing

### Manual Health Testing
```bash
# Test container health directly
docker exec -it <container> /health-monitor.sh test

# Get health report
curl http://<container-ip>:8080/health
```

### Integration Testing
```bash
# Run comprehensive monitoring tests
./scripts/test_monitoring_integration.sh

# Test specific namespace
NAMESPACE=test ./scripts/test_monitoring_integration.sh
```

### Unit Testing
```bash
cd backend && npm test
```

Tests cover:
- Kubernetes discovery functionality
- Health monitoring and recovery
- Error handling and fallbacks
- API endpoint responses

## Troubleshooting

### Common Issues

#### Auto-Discovery Not Working
1. Check RBAC permissions: `kubectl auth can-i list pods --as=system:serviceaccount:loco:loco-backend`
2. Verify pod labels: `kubectl get pods -l app.kubernetes.io/component=emulator`
3. Check backend logs: `kubectl logs deployment/loco-backend`

#### Health Endpoints Unreachable
1. Verify port exposure: `kubectl get svc loco-emulator`
2. Test port-forward: `kubectl port-forward pod/loco-emulator-0 8080:8080`
3. Check container logs: `kubectl logs pod/loco-emulator-0`

#### Recovery Not Working
1. Check recovery attempt limits in backend logs
2. Verify failure classification is correct
3. Test manual recovery: `curl -X POST http://backend/api/quality/recover/instance-0`

### Debug Commands
```bash
# Check discovery status
curl http://backend:3000/api/instances/discovery-info

# Get detailed health
curl http://backend:3000/api/quality/deep-health

# Monitor backend logs
kubectl logs -f deployment/loco-backend

# Check emulator health
kubectl exec pod/loco-emulator-0 -- /health-monitor.sh report
```

## Performance Considerations

- Health monitoring adds ~2% CPU overhead per container
- Network usage: ~1KB/s per instance for health checks
- Discovery refresh: Every 30 seconds (configurable)
- Recovery attempts: Limited to 3 per instance per hour
- Cache TTL: 30 seconds for discovered instances

## Future Enhancements

- Predictive failure detection using ML
- Advanced recovery strategies
- Historical health trend analysis
- Custom health check definitions
- Integration with external monitoring systems