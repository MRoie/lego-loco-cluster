# Stream Quality Monitoring

This document describes the video/audio quality monitoring system implemented for the Lego Loco cluster streaming infrastructure.

## Overview

The Stream Quality Monitor provides real-time monitoring and assessment of video/audio streaming quality across all QEMU instances in the cluster. It includes both backend probing services and frontend quality metrics collection.

## Architecture

### Backend Components

#### StreamQualityMonitor Service (`backend/services/streamQualityMonitor.js`)

Core monitoring service that:
- **Availability Probing**: Tests VNC port connectivity for all instances
- **Latency Measurement**: Measures connection establishment times  
- **Quality Estimation**: Estimates video frame rates and audio quality based on network conditions
- **Metrics Collection**: Aggregates quality data across all instances
- **Auto-monitoring**: Runs continuous probes every 5 seconds

#### API Endpoints

- `GET /api/quality/metrics` - Get detailed quality metrics for all instances
- `GET /api/quality/metrics/:instanceId` - Get metrics for a specific instance  
- `GET /api/quality/summary` - Get aggregated quality summary across all instances
- `POST /api/quality/monitor/start` - Start the monitoring service
- `POST /api/quality/monitor/stop` - Stop the monitoring service

### Frontend Components

#### Enhanced useWebRTC Hook (`frontend/src/hooks/useWebRTC.js`)

Extended to provide:
- **RTCStats Collection**: Real-time WebRTC connection statistics
- **Video Quality Metrics**: Frame rate, resolution, bitrate monitoring
- **Audio Quality Assessment**: Audio level detection and quality estimation
- **Connection Quality Tracking**: Packet loss, jitter, latency measurements
- **Auto-reconnection**: Intelligent reconnection with quality adaptation

#### StreamQualityMonitor Component (`frontend/src/components/StreamQualityMonitor.jsx`)

Dashboard component featuring:
- **Real-time Metrics Display**: Live quality metrics for all instances
- **Quality Summary**: Aggregated availability and performance overview
- **Visual Indicators**: Color-coded quality status (excellent/good/fair/poor/error)
- **Historical Data**: Timestamp tracking for quality trends
- **Error Reporting**: Detailed error information for troubleshooting

## Quality Metrics

### Availability Metrics
- **VNC Connectivity**: TCP port reachability test
- **Stream Availability**: HTTP endpoint accessibility
- **Connection State**: WebRTC peer connection status

### Performance Metrics
- **Connection Latency**: Round-trip time for connection establishment
- **Video Frame Rate**: Estimated or measured frames per second
- **Audio Quality**: Categorical assessment (excellent/good/fair/poor/unavailable)
- **Packet Loss**: Percentage of lost packets in transmission
- **Jitter**: Network delay variation in milliseconds
- **Bitrate**: Data transmission rate for video streams
- **Resolution**: Video frame dimensions

### Quality Categories
- **Excellent**: Latency < 50ms, 30fps, no packet loss
- **Good**: Latency < 100ms, 25fps, minimal packet loss
- **Fair**: Latency < 200ms, 20fps, acceptable packet loss  
- **Poor**: Latency > 200ms, 15fps, significant packet loss
- **Error/Unavailable**: Connection failed or service unreachable

## Usage

### Backend Monitoring

The monitoring service starts automatically when the backend server starts:

```javascript
// Automatically started
console.log("🔍 Starting stream quality monitoring service...");
qualityMonitor.start();
```

### API Usage Examples

```bash
# Get quality summary
curl http://localhost:3001/api/quality/summary

# Get all instance metrics  
curl http://localhost:3001/api/quality/metrics

# Get specific instance metrics
curl http://localhost:3001/api/quality/metrics/instance-0

# Control monitoring service
curl -X POST http://localhost:3001/api/quality/monitor/start
curl -X POST http://localhost:3001/api/quality/monitor/stop
```

### Frontend Integration

```jsx
import { useWebRTC } from './hooks/useWebRTC';

function StreamComponent({ instanceId }) {
  const { videoRef, audioLevel, loading, connectionQuality } = useWebRTC(instanceId);
  
  return (
    <div>
      <video ref={videoRef} />
      <div>Quality: {connectionQuality.connectionState}</div>
      <div>Frame Rate: {connectionQuality.frameRate}fps</div>
      <div>Latency: {connectionQuality.latency}ms</div>
    </div>
  );
}
```

### Quality Dashboard

```jsx
import StreamQualityMonitor from './components/StreamQualityMonitor';

function AdminDashboard() {
  return (
    <div>
      <h1>Cluster Status</h1>
      <StreamQualityMonitor />
    </div>
  );
}
```

## Testing

### Automated Tests

Run the quality monitoring test suite:

```bash
cd tests
node test-stream-quality-monitoring.js
```

Tests include:
- Service initialization and configuration
- Instance probing and metrics collection  
- API endpoint functionality
- Error handling and recovery
- Quality estimation algorithms

### Manual Testing

1. Start the backend server: `npm start`
2. Monitor quality metrics: `curl http://localhost:3001/api/quality/summary`
3. Check individual instances: `curl http://localhost:3001/api/quality/metrics/instance-0`
4. View frontend dashboard: Include `<StreamQualityMonitor />` in your React app

## Configuration

### Instance Configuration

Instances are configured in `config/instances.json`:

```json
{
  "id": "instance-0",
  "streamUrl": "http://localhost:6080/vnc0", 
  "vncUrl": "localhost:5901",
  "name": "Windows 98 - Game Server"
}
```

### Monitoring Configuration

Monitoring settings can be adjusted in `streamQualityMonitor.js`:

```javascript
class StreamQualityMonitor {
  constructor(configDir = '../config') {
    this.probeInterval = 5000; // 5 seconds between probes
    this.connectionTimeout = 3000; // 3 second probe timeout
  }
}
```

## Future Enhancements

See `AGENTS.md` for detailed sequential prompts covering:

- Advanced WebRTC statistics integration
- Quality-adaptive streaming with dynamic adjustment
- Real-time quality dashboard with historical trends
- QEMU audio/video subsystem health probing
- Comprehensive quality testing suite
- Intelligent failure detection and recovery
- Performance profiling and optimization

## Troubleshooting

### Common Issues

1. **No metrics available**: Ensure instances are configured and reachable
2. **Connection timeouts**: Check network connectivity and VNC service status
3. **Inaccurate quality estimates**: Network conditions may affect measurement accuracy
4. **API errors**: Verify backend server is running and monitoring service is started

### Debug Information

Enable debug logging:

```javascript
// In development mode, detailed metrics are logged
if (process.env.NODE_ENV === 'development') {
  console.log('Debug info:', metrics);
}
```

Monitor server logs for probe results:
```
🔍 Starting Stream Quality Monitor
Probe failed for instance-0: connect ECONNREFUSED 127.0.0.1:5901
✓ Quality summary: { total: 9, available: 0, availabilityPercent: 0 }
```