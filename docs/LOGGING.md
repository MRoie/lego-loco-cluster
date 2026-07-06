# Lego Loco Cluster Logging System

## Overview

The Lego Loco Cluster application uses a comprehensive structured logging system based on Winston for backend services and a custom browser-compatible logger for frontend components. This unified approach provides consistent log formats, configurable log levels, and better observability across the entire application stack.

## Architecture

### Multi-Environment Support

The logging system supports different execution contexts:

- **Backend Services**: Full Winston logging with file rotation and persistence
- **Frontend Components**: Browser-compatible structured logging for React components
- **Test Suites**: Console-only logging with appropriate context for CI/CD environments
- **Node.js Scripts**: Shared logger utilities for mock servers and utility scripts

### Logger Types

#### 1. Backend Logger (`backend/utils/logger.js`)
Full-featured Winston logger for server-side code:
- Daily rotating file logs with configurable retention
- JSON format for log aggregation and analysis
- Console output for development with colored formatting
- Environment-based configuration

#### 2. Shared Logger (`utils/logger.js`)
Factory functions for creating consistent loggers:
- `createLogger(serviceName)` - Full Winston logger for Node.js scripts
- `createTestLogger(serviceName)` - Console-only logger for test environments
- Standardized service naming and context management

#### 3. Frontend Logger (`frontend/src/utils/logger.js`)
Browser-compatible structured logging:
- Environment-aware log levels (debug in dev, warn in production)
- Structured context preservation
- PostMessage integration for iframe debugging
- Compatible with Winston log structure for consistency

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `info` | Minimum log level for backend services |
| `VITE_LOG_LEVEL` | `debug` (dev) / `warn` (prod) | Frontend log level |
| `NODE_ENV` | `development` | Environment mode affecting log output |

### Log Levels (in order of severity)

1. **debug** - Detailed information for diagnosing problems
2. **info** - General information about application flow
3. **warn** - Something unexpected happened but application continues
4. **error** - Error events but application can continue running

## Usage Examples

### Backend Services

```javascript
// Import the default logger
const logger = require('../utils/logger');

// Basic logging with context
logger.info('Server started', { port: 3001, environment: process.env.NODE_ENV });
logger.warn('High memory usage detected', { usage: '85%', threshold: '80%' });
logger.error('Database connection failed', { error: err.message, retryCount: 3 });

// Debug logging (only visible when LOG_LEVEL=debug)
logger.debug('Processing request', { userId, endpoint: '/api/instances' });
```

### Shared Utilities and Scripts

```javascript
// Create a service-specific logger
const { createLogger } = require('../utils/logger');
const logger = createLogger('mock-stream-server');

// Log with service context
logger.info('Mock server started', { url: 'http://localhost:6080', port: 6080 });
logger.error('Failed to bind to port', { port: 6080, error: 'EADDRINUSE' });
```

### Test Files

```javascript
// Create a test-specific logger (console-only)
const { createTestLogger } = require('../utils/logger');
const logger = createTestLogger('vnc-cluster-test');

// Test logging with context
logger.info('Starting VNC connection test', { instanceName: 'instance-0' });
logger.debug('VNC handshake completed', { 
  framebufferSize: { width: 1024, height: 768 },
  desktopName: 'Windows 98'
});
```

### Frontend Components

```javascript
// Import the frontend logger
import { createLogger } from '../utils/logger.js';

const logger = createLogger('NoVNCViewer');

// Component lifecycle logging
logger.info('NoVNC connected successfully', { instanceId: 'instance-0' });
logger.warn('Connection quality degraded', { latency: 150, targetId: 'instance-1' });
logger.error('Failed to establish WebRTC connection', { 
  targetId: 'instance-2', 
  error: 'ICE connection failed' 
});

// WebRTC debugging
logger.debug('Peer connection state changed', { 
  targetId: 'instance-0',
  connectionState: 'connected',
  iceConnectionState: 'completed'
});
```

## Log Output Formats

### Console Output (Development)

```
2025-01-13 05:08:41 [info] [lego-loco-backend]: Server started {"port":3001,"environment":"development"}
2025-01-13 05:08:42 [debug] [NoVNCViewer]: WebSocket connection established {"instanceId":"instance-0"}
2025-01-13 05:08:43 [warn] [useWebRTC]: Failed to get WebRTC stats {"targetId":"instance-1","error":"Invalid target"}
```

### File Output (JSON)

```json
{"level":"info","message":"Server started","service":"lego-loco-backend","port":3001,"environment":"development","timestamp":"2025-01-13 05:08:41"}
{"level":"debug","message":"WebSocket connection established","service":"lego-loco-frontend","instanceId":"instance-0","timestamp":"2025-01-13 05:08:42"}
{"level":"warn","message":"Failed to get WebRTC stats","service":"lego-loco-frontend","targetId":"instance-1","error":"Invalid target","timestamp":"2025-01-13 05:08:43"}
```

## File Management

### Backend File Logs

Logs are stored in `backend/logs/` directory:

- **Application logs**: `application-YYYY-MM-DD.log`
  - All log levels (based on `LOG_LEVEL`)
  - 14-day retention
  - 20MB max file size with automatic rotation

- **Error logs**: `error-YYYY-MM-DD.log`
  - Error level only
  - 30-day retention (longer for debugging)
  - 20MB max file size with automatic rotation

### Log Directory Structure

```
backend/logs/
├── application-2025-01-13.log
├── application-2025-01-12.log
├── error-2025-01-13.log
└── error-2025-01-12.log
```

## Development Guidelines

### Best Practices

1. **Use Structured Context**: Always include relevant metadata
   ```javascript
   // Good
   logger.info('User authenticated', { userId, sessionId, ipAddress });
   
   // Avoid
   logger.info(`User ${userId} authenticated from ${ipAddress}`);
   ```

2. **Choose Appropriate Log Levels**:
   - `debug`: Development debugging, verbose internal state
   - `info`: Normal application flow, user actions, system events
   - `warn`: Recoverable errors, performance issues, deprecated usage
   - `error`: Serious errors requiring attention

3. **Include Error Context**:
   ```javascript
   // Good
   logger.error('Database query failed', { 
     query: 'SELECT * FROM users', 
     error: err.message,
     stack: err.stack,
     executionTime: '1.2s'
   });
   ```

4. **Use Service-Specific Loggers**:
   ```javascript
   // Create component-specific loggers for better filtering
   const logger = createLogger('InstanceManager');
   const logger = createLogger('VNCBridge');
   const logger = createLogger('WebRTCHandler');
   ```

### Migration from Console Statements

When updating legacy code, replace console statements with structured logging:

```javascript
// Before
console.log('VNC connected to instance-0');
console.error('Connection failed:', error);

// After
logger.info('VNC connection established', { instanceId: 'instance-0' });
logger.error('VNC connection failed', { instanceId: 'instance-0', error: error.message });
```

## Environment-Specific Configuration

### Development
```bash
LOG_LEVEL=debug npm start
VITE_LOG_LEVEL=debug npm run dev
```

### Staging
```bash
LOG_LEVEL=info npm start
VITE_LOG_LEVEL=info npm run build
```

### Production
```bash
LOG_LEVEL=warn npm start
VITE_LOG_LEVEL=error npm run build
```

## Monitoring and Analysis

### Log Aggregation

The JSON format enables easy integration with log aggregation systems:

- **ELK Stack**: Elasticsearch, Logstash, Kibana
- **Grafana Loki**: For cloud-native log aggregation
- **Splunk**: Enterprise log management
- **Cloud Services**: AWS CloudWatch, Azure Monitor, GCP Cloud Logging

### Query Examples

Search for errors in a specific service:
```json
{
  "query": {
    "bool": {
      "must": [
        { "term": { "level": "error" } },
        { "term": { "service": "lego-loco-backend" } }
      ]
    }
  }
}
```

Filter by time range and instance:
```json
{
  "query": {
    "bool": {
      "must": [
        { "range": { "timestamp": { "gte": "2025-01-13T00:00:00" } } },
        { "term": { "instanceId": "instance-0" } }
      ]
    }
  }
}
```

## Troubleshooting

### Common Issues

1. **Missing Log Files**: Ensure the `backend/logs` directory exists and is writable
2. **Log Level Not Working**: Check environment variable spelling and case
3. **Frontend Logs Not Appearing**: Verify `VITE_LOG_LEVEL` is set appropriately
4. **Performance Impact**: In production, use `warn` or `error` levels to reduce I/O

### Debug Information

View current log configuration:
```javascript
// Backend
console.log('Log Level:', process.env.LOG_LEVEL || 'info');
console.log('Environment:', process.env.NODE_ENV || 'development');

// Frontend
console.log('Frontend Log Level:', import.meta.env?.VITE_LOG_LEVEL);
console.log('Development Mode:', import.meta.env?.DEV);
```

## Integration with CI/CD

### Test Environment Logging

Tests use console-only loggers to avoid file I/O in CI environments:

```javascript
const logger = createTestLogger('integration-test');
logger.info('Test completed', { 
  testName: 'VNC Connection Test',
  duration: '2.3s',
  status: 'passed'
});
```

### GitHub Actions Integration

The logging system automatically adjusts for CI environments:
- File logging disabled in test environments
- Console output optimized for GitHub Actions log viewer
- Structured logs help with automated log analysis

This comprehensive logging system provides the foundation for effective debugging, monitoring, and operational visibility across the entire Lego Loco Cluster application.