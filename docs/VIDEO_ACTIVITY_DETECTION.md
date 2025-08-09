# VNC Video Activity Detection System

## Overview

The enhanced backend now includes a sophisticated video activity detection system that ensures containers only remain healthy when VNC servers are actively streaming video content. This system provides real-time monitoring of VNC streams and ties container health directly to video activity.

## Key Features

### 🎬 Real-time Video Stream Monitoring
- **Bytes-per-second tracking**: Monitors bandwidth usage to detect active video streams
- **Video frame detection**: Identifies large data chunks (>1KB) as potential video frames
- **Activity history**: Maintains a 30-second rolling window of stream activity
- **Frame counting**: Tracks the number of video frames transmitted

### 🔍 Health Status Classification
The system classifies connections into different health states:

- **Healthy**: Active video streaming with adequate bandwidth (>1KB/s) and recent frames (<1 minute)
- **Degraded**: Connection exists but no recent video activity
- **Unhealthy**: No connections or failed connections
- **No Connections**: No VNC connections established

### 📊 Container Health Probes
Kubernetes health probes now validate video activity:

- **Startup Probe**: `/health/container` - Validates initial video stream setup
- **Liveness Probe**: `/health/container` - Ensures ongoing video activity
- **Readiness Probe**: `/health/container` - Confirms video stream readiness

## Technical Implementation

### Video Activity Detection Algorithm

```javascript
// Video activity thresholds
const videoActivityThreshold = 1000; // 1KB/s minimum
const videoActivityWindow = 30000;   // 30-second window
const frameTimeout = 60000;          // 1-minute frame timeout

// Health determination
const hasVideoStream = bytesPerSecond > videoActivityThreshold;
const hasRecentFrames = lastVideoFrame && (now - lastVideoFrame) < frameTimeout;
const isHealthy = hasVideoStream && hasRecentFrames;
```

### Metrics Collection

The system tracks comprehensive metrics for each VNC connection:

```javascript
videoActivity: {
  bytesPerSecond: 0,        // Current bandwidth usage
  lastVideoFrame: null,      // Timestamp of last video frame
  frameCount: 0,            // Total frames detected
  totalBytes: 0,            // Total bytes transferred
  activityHistory: []       // Rolling window of activity
}
```

### Health Check Endpoints

#### `/health/container` - Container Health Probe
Returns 200 only when video activity is detected:

```json
{
  "status": "healthy",
  "videoActivity": true,
  "healthyConnections": 1,
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

#### `/health/metrics` - Detailed Metrics
Provides comprehensive video activity data:

```json
{
  "containerHealth": "healthy",
  "vncConnections": {
    "globalStatus": "healthy",
    "totalConnections": 1,
    "healthyConnections": 1,
    "connections": [
      {
        "instanceId": "qemu-softgpu",
        "isHealthy": true,
        "videoActivity": {
          "bytesPerSecond": 2048,
          "frameCount": 150,
          "lastVideoFrame": 1704067200000,
          "hasRecentFrames": true,
          "hasVideoStream": true
        }
      }
    ]
  }
}
```

## Deployment

### Building Enhanced Backend

```bash
# Build the enhanced backend image
docker build -t compose-backend:enhanced ./backend

# Deploy using the enhanced deployment script
./scripts/deploy-enhanced-backend.sh
```

### Kubernetes Deployment

The enhanced backend automatically uses the new health probes:

```yaml
livenessProbe:
  httpGet:
    path: /health/container
    port: 3001
  initialDelaySeconds: 60
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3
```

## Testing

### Video Activity Test Suite

Run comprehensive video activity detection tests:

```bash
# Test video activity detection
node tests/test-video-activity.js

# Test enhanced health checks
node tests/test-enhanced-health.js
```

### Manual Testing

Test container health based on video activity:

```bash
# Check container health (requires active video streams)
curl http://localhost:3001/health/container

# Get detailed video metrics
curl http://localhost:3001/health/metrics

# Test basic health (includes video activity validation)
curl http://localhost:3001/health
```

## Monitoring and Debugging

### Log Output

The system provides detailed logging for video activity:

```
VNC Health Status: healthy (1/1 healthy, video activity: true)
VNC qemu-softgpu: 2048 B/s, 150 frames, last frame: 5s ago
VNC WS->TCP qemu-softgpu: 2048 bytes (video frame?)
VNC TCP->WS qemu-softgpu: 2048 bytes (video frame?)
```

### Health Status Transitions

The system automatically transitions between health states:

1. **No Activity**: Container starts unhealthy
2. **Connection Established**: Status becomes degraded
3. **Video Activity Detected**: Status becomes healthy
4. **Activity Stops**: Status returns to degraded/unhealthy

## Configuration

### Environment Variables

```bash
# Video activity thresholds (optional, defaults shown)
VIDEO_ACTIVITY_THRESHOLD=1000    # Minimum bytes/second
VIDEO_ACTIVITY_WINDOW=30000      # Activity window (ms)
FRAME_TIMEOUT=60000              # Frame timeout (ms)
HEALTH_CHECK_INTERVAL=10000      # Health check interval (ms)
```

### Customization

Modify video activity detection parameters in `backend/server-enhanced.js`:

```javascript
class VNCHealthMonitor {
  constructor() {
    this.videoActivityThreshold = 1000; // Adjust for your VNC setup
    this.healthCheckInterval = 10000;   // Health check frequency
    this.videoActivityWindow = 30000;   // Activity window
  }
}
```

## Troubleshooting

### Common Issues

1. **Container Always Unhealthy**
   - Check if VNC servers are running and streaming
   - Verify bandwidth threshold is appropriate for your setup
   - Check logs for connection errors

2. **False Positives**
   - Adjust `videoActivityThreshold` for your VNC configuration
   - Modify frame detection logic for your specific VNC implementation

3. **Health Check Timeouts**
   - Increase probe timeouts in Kubernetes deployment
   - Check network connectivity between backend and VNC servers

### Debug Commands

```bash
# Check current video activity
curl -s http://localhost:3001/health/metrics | jq '.vncConnections.connections[].videoActivity'

# Monitor health status changes
watch -n 5 'curl -s http://localhost:3001/health/container | jq .'

# Test with simulated video data
node tests/test-video-activity.js
```

## Benefits

### 🎯 Precise Health Validation
- Containers only healthy when actively streaming video
- Prevents false positives from idle connections
- Ensures service quality for end users

### 📈 Performance Monitoring
- Real-time bandwidth tracking
- Frame rate monitoring
- Connection quality assessment

### 🔄 Automatic Recovery
- Health status automatically updates based on video activity
- Graceful handling of connection failures
- Kubernetes integration for automatic restarts

### 🛡️ Production Ready
- Comprehensive error handling
- Resource limits and monitoring
- Graceful shutdown procedures

## Future Enhancements

- **Video Quality Metrics**: Frame rate, resolution, compression ratio
- **Bandwidth Optimization**: Adaptive quality based on network conditions
- **Multi-stream Support**: Enhanced monitoring for multiple concurrent streams
- **Alerting Integration**: Integration with monitoring systems for video activity alerts 