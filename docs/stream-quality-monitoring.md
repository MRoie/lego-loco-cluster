# Stream Quality Monitoring

This document describes the comprehensive video/audio quality monitoring system for QEMU streaming instances.

## Overview

The Stream Quality Monitor provides real-time assessment of QEMU instance streaming quality, including:

- **VNC Connectivity Testing** - Tests actual VNC port connectivity and responsiveness
- **Audio Detection and Quality Assessment** - Detects audio capabilities and measures audio quality
- **Control Responsiveness Testing** - Tests VNC control inputs (mouse/keyboard) responsiveness  
- **Network Quality Metrics** - Measures latency, packet loss, and jitter
- **Individual Instance Indicators** - Shows quality status on each instance card
- **Comprehensive Dashboard** - Central monitoring view for all instances

## Features

### Backend Quality Monitoring Service

The `StreamQualityMonitor` service continuously probes all instances:

```javascript
const qualityMonitor = new StreamQualityMonitor('/config');
qualityMonitor.start();
```

**Monitoring Capabilities:**
- VNC port connectivity via TCP socket testing
- WebSocket VNC proxy testing for actual protocol validation
- Audio detection using WebAudio API capabilities testing
- Control responsiveness via synthetic mouse/keyboard event testing
- Connection latency measurement and quality estimation
- Automatic error detection and recovery

**Quality Metrics Tracked:**
- `availability.vnc` - VNC service availability
- `availability.stream` - Stream endpoint availability  
- `availability.audio` - Audio detection status
- `availability.controls` - Control input availability
- `quality.connectionLatency` - Network latency in milliseconds
- `quality.videoFrameRate` - Estimated video frame rate
- `quality.audioQuality` - Overall audio quality (excellent/good/fair/poor/error/unavailable)
- `quality.audioLevel` - Audio level detection (0.0-1.0)
- `quality.controlsResponsive` - Control input responsiveness status
- `quality.packetLoss` - Estimated packet loss percentage
- `quality.jitter` - Network jitter in milliseconds

### Frontend Quality Integration

#### Individual Instance Cards

Each instance card now displays real-time quality indicators:

```jsx
import QualityIndicator from './components/QualityIndicator';

<QualityIndicator instanceId={instance.id} compact={true} />
```

**Quality Indicator Features:**
- Color-coded quality status (green/blue/yellow/orange/red)
- VNC availability status
- Audio detection indicator
- Control responsiveness status
- Connection latency display
- Real-time updates every 5 seconds

#### Enhanced VNC Viewer

The `ReactVNCViewer` component now includes:

- **Audio Capabilities Testing** - Tests browser audio support and VNC audio streams
- **Control Responsiveness Testing** - Periodically tests control input handling
- **Enhanced Status Indicators** - Shows audio, video, and control status separately
- **Improved Error Handling** - Better error reporting and recovery

### API Endpoints

#### Get All Instance Metrics
```bash
GET /api/quality/metrics
```

Returns quality metrics for all instances:
```json
{
  "instance-0": {
    "instanceId": "instance-0",
    "timestamp": "2025-08-07T23:17:30.476Z",
    "availability": {
      "vnc": true,
      "stream": true,
      "audio": true,
      "controls": true
    },
    "quality": {
      "connectionLatency": 45,
      "videoFrameRate": 30,
      "audioQuality": "excellent",
      "audioLevel": 0.7,
      "controlsResponsive": true,
      "packetLoss": 0.001,
      "jitter": 2.5
    },
    "errors": []
  }
}
```

#### Get Instance-Specific Metrics
```bash
GET /api/quality/metrics/:instanceId
```

Returns quality metrics for a specific instance.

#### Get Quality Summary
```bash
GET /api/quality/summary
```

Returns aggregated quality overview:
```json
{
  "total": 9,
  "available": 6,
  "availabilityPercent": 66.7,
  "averageLatency": 52,
  "qualityDistribution": {
    "excellent": 3,
    "good": 2,
    "fair": 1,
    "unavailable": 3
  }
}
```

#### Control Monitoring Service
```bash
POST /api/quality/monitor/start
POST /api/quality/monitor/stop
```

Start or stop the quality monitoring service.

## Quality Assessment Algorithm

### Audio Quality Determination

The system determines audio quality based on multiple factors:

1. **Audio Detection** - Tests browser AudioContext support and VNC audio capabilities
2. **Control Responsiveness** - Tests VNC control input handling
3. **Network Latency** - Measures connection response time
4. **Error Rate** - Tracks connection and functionality errors

**Quality Levels:**
- `excellent` - Low latency (<50ms), audio detected, controls responsive
- `good` - Moderate latency (<100ms), audio detected, controls responsive  
- `fair` - Higher latency (<200ms) OR audio detected but controls unresponsive
- `poor` - High latency (>200ms) OR controls responsive but no audio
- `error` - Neither audio nor controls working properly
- `unavailable` - VNC connection failed

### Control Testing

The system performs non-intrusive control testing:

1. **Synthetic Event Testing** - Dispatches test mouse/keyboard events to VNC canvas
2. **Event Handler Validation** - Verifies event handlers are responsive
3. **Periodic Testing** - Tests every 10 seconds when connected and active
4. **VR Controller Support** - Special handling for VR controller inputs

### Network Quality Estimation

Network quality metrics are estimated based on:

- **Connection Latency** - Direct TCP socket connection timing
- **Packet Loss** - Derived from latency and functionality test results
- **Jitter** - Calculated from latency variations and functional responsiveness

## Testing

The monitoring system includes comprehensive automated tests:

```bash
cd backend
npm test
```

**Test Coverage:**
- Audio detection and quality assessment
- Control responsiveness testing
- Network quality measurement
- Error handling and recovery
- Quality summary generation
- API endpoint functionality

## Configuration

### Monitoring Intervals

- **Probe Interval** - 5 seconds (configurable in `StreamQualityMonitor`)
- **Control Test Interval** - 10 seconds when VNC is active
- **Frontend Update Interval** - 5 seconds for UI refreshes

### Quality Thresholds

Quality thresholds can be adjusted in `estimateQualityMetrics()`:

```javascript
// Latency thresholds (milliseconds)
const EXCELLENT_THRESHOLD = 50;
const GOOD_THRESHOLD = 100;
const FAIR_THRESHOLD = 200;

// Audio level thresholds (0.0-1.0)
const MIN_AUDIO_LEVEL = 0.2;
const GOOD_AUDIO_LEVEL = 0.3;
```

## Troubleshooting

### Common Issues

**No Quality Data**
- Verify monitoring service is started: `POST /api/quality/monitor/start`
- Check instances.json configuration file exists
- Ensure backend server is running on correct port

**Audio Not Detected**
- Check browser audio permissions
- Verify VNC connection is established
- Test with audio-enabled browser (Chrome/Firefox)

**Controls Not Responsive**
- Check VNC canvas element exists
- Verify browser allows synthetic events
- Test with different VNC client settings

**High Latency/Poor Quality**
- Check network connectivity to VNC hosts
- Verify QEMU instances are running
- Monitor system resource usage

### Debug Mode

Enable debug mode for detailed logging:

```bash
NODE_ENV=development npm run dev
```

This provides additional console output for monitoring operations and quality assessments.

## Integration with VR

The quality monitoring system integrates with VR controllers:

- **VR Event Handling** - Custom VR events trigger quality tests
- **VR-Specific Control Testing** - Tests VR controller input responsiveness
- **VR Quality Indicators** - Quality status visible in VR interface

See `ReactVNCViewer.jsx` for VR integration details.

## Future Enhancements

Planned improvements include:

1. **Advanced Video Analysis** - Real video frame rate detection
2. **Audio Level Monitoring** - Real-time audio level measurement  
3. **Network Bandwidth Testing** - Actual bandwidth measurement
4. **Historical Quality Tracking** - Quality metrics over time
5. **Alert System** - Notifications for quality degradation
6. **Quality-Based Load Balancing** - Route users to best-performing instances

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