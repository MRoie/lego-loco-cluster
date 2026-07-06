# SRE-Focused Kubernetes Probe Testing

This document describes the Site Reliability Engineering (SRE) approach to testing Kubernetes probes in the Lego Loco Cluster project.

## Overview

The `test-emulator-probes.sh` script implements comprehensive SRE testing for Kubernetes probes, measuring actual service behavior rather than static configuration validation.

## SRE Principles Applied

### Service Level Objectives (SLOs)
- **Startup Probe Success Rate**: ≥95% of pods should start successfully within 5 minutes
- **Liveness Probe Response Time**: ≤500ms for health check responses
- **Readiness Probe Response Time**: ≤300ms for readiness validation
- **Startup Time**: ≤300 seconds maximum startup time
- **Recovery Time**: ≤60 seconds maximum recovery after failure
- **Overall Probe Success Rate**: ≥99% probe success rate

### Service Level Indicators (SLIs)
- Response time measurements for each probe type
- Success/failure rates for probe endpoints
- Startup and recovery time tracking
- Cross-service coordination metrics

## Service-Specific Probe Strategies

### Emulator Service Probes
- **Startup Probe**: Validates QEMU boot process, video/audio subsystems (30 attempts × 10s = 5min max)
- **Liveness Probe**: Detects QEMU deadlocks and hung processes (15s intervals, 3 failures = restart)
- **Readiness Probe**: Ensures all subsystems operational before traffic routing (10s intervals)

### Backend Service Probes
- **Health Endpoint**: Simple availability check (`/health`)
- **API Readiness**: Full API functionality validation (`/api/instances`)
- **Deep Health**: Comprehensive monitoring integration (`/api/quality/deep-health`)

### Cross-Service Coordination
- Tests backend's ability to monitor emulator health
- Validates service discovery and health aggregation
- Measures end-to-end monitoring pipeline

## Usage

### Prerequisites
```bash
# For Kubernetes testing
kubectl cluster-info

# For Docker Compose testing  
docker-compose ps

# For development testing
curl -f http://localhost:3001/health
```

### Running Tests

#### Basic SRE Testing
```bash
./tests/test-emulator-probes.sh
```

#### Kubernetes Environment
```bash
# Deploy services first
kubectl apply -f k8s/

# Run comprehensive SRE tests
./tests/test-emulator-probes.sh
```

#### Docker Compose Environment
```bash
# Start services
docker-compose up -d

# Run SRE tests
./tests/test-emulator-probes.sh
```

#### Development Environment
```bash
# Start backend
cd backend && npm start &

# Start frontend  
cd frontend && npm run dev &

# Run limited SRE tests
./tests/test-emulator-probes.sh
```

## Test Categories

### 1. Environment Discovery
- Detects deployment environment (Kubernetes, Docker Compose, Development)
- Adapts test strategy based on available services
- Validates service accessibility

### 2. Service-Specific Testing
- **Backend**: Health endpoints, API availability, response times
- **Emulator**: QEMU subsystem validation, health monitoring integration
- **Cross-Service**: Service discovery and health aggregation

### 3. Timing and Performance
- Measures actual probe response times
- Validates SLO compliance
- Tracks startup and recovery times

### 4. Failure Scenarios
- Tests probe failure detection
- Validates recovery mechanisms
- Measures Mean Time To Recovery (MTTR)

### 5. Reliability Assessment
- Calculates error budgets
- Provides reliability scoring (A+ to C)
- Generates actionable recommendations

## Output Format

```
🔬 SRE-Focused Kubernetes Probe Reliability Test Suite
======================================================

[SLO] Service Level Objectives:
  startup_probe_success_rate: 95
  liveness_probe_response_time_ms: 500
  [...]

[TEST] Environment and Service Discovery
[PASS] Kubernetes environment detected (45ms)

[SLI] Backend health endpoint: 25ms <= 500ms ✅
[SLI] Emulator health response: 120ms <= 300ms ✅

📊 SRE Test Summary:
   Tests run: 6
   Tests passed: 6  
   SLO violations: 0
   Success rate: 100%
   Reliability score: A+
   Error budget status: HEALTHY
```

## Integration with CI/CD

### GitHub Actions Integration
```yaml
- name: SRE Probe Testing
  run: |
    kubectl apply -f k8s/
    kubectl wait --for=condition=ready pod -l app=loco-emulator --timeout=300s
    ./tests/test-emulator-probes.sh
```

### Monitoring Integration
- Export metrics to Prometheus/Grafana
- Set up alerting for SLO violations
- Track reliability trends over time

## Best Practices

### For Development
1. Run SRE tests before committing probe configuration changes
2. Validate SLO compliance with actual service response times
3. Test failure scenarios locally

### For Production
1. Run SRE tests as part of deployment validation
2. Monitor SLO compliance continuously
3. Set up alerting for error budget violations
4. Review and adjust SLOs based on actual performance data

### For Debugging
1. Use SRE test output to identify performance bottlenecks
2. Analyze SLI measurements to tune probe configurations
3. Compare reliability scores across environments

## Continuous Improvement

### Monitoring Recommendations
- Track probe success rates over time
- Monitor response time trends
- Set up dashboards for SLO compliance

### SLO Tuning
- Review SLO targets quarterly based on actual performance
- Adjust probe timeouts based on measured response times
- Balance reliability requirements with resource efficiency

### Failure Analysis
- Investigate SLO violations for root cause
- Update probe strategies based on failure patterns
- Improve error budgets through proactive monitoring