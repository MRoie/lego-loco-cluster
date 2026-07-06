#!/bin/bash

# Basic VNC connectivity test for minikube cluster
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCREENSHOT_DIR="./vnc-screenshots"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="${SCREENSHOT_DIR}/vnc-test-report-${TIMESTAMP}.txt"

# Ensure screenshot directory exists
mkdir -p "$SCREENSHOT_DIR"

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$REPORT_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$REPORT_FILE"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$REPORT_FILE"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1" | tee -a "$REPORT_FILE"
}

# Initialize report
echo "=== VNC Cluster Connectivity Test Report ===" > "$REPORT_FILE"
echo "Generated: $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

log "Starting VNC cluster connectivity tests..."

# Check if minikube is running
log "Checking minikube status..."
if ! minikube status >/dev/null 2>&1; then
    error "Minikube is not running"
    exit 1
fi
success "Minikube is running"

# Check cluster status
log "Checking cluster status..."
kubectl get pods -n loco -o wide | tee -a "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Check services
log "Checking services..."
kubectl get svc -n loco | tee -a "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Get frontend service URL
log "Getting frontend service URL..."
FRONTEND_URL=$(minikube service loco-loco-frontend -n loco --url 2>/dev/null || echo "")
if [ -z "$FRONTEND_URL" ]; then
    error "Could not get frontend service URL"
    exit 1
fi
success "Frontend URL: $FRONTEND_URL"

# Extract port from URL
FRONTEND_PORT=$(echo "$FRONTEND_URL" | sed 's/.*://')
log "Frontend port: $FRONTEND_PORT"

# Test basic connectivity
log "Testing basic connectivity to frontend..."
if curl -s --connect-timeout 10 "$FRONTEND_URL" >/dev/null; then
    success "Frontend is accessible"
else
    error "Frontend is not accessible"
fi

# Test VNC proxy endpoints
log "Testing VNC proxy endpoints..."
INSTANCES=("instance-0" "instance-1" "instance-2" "instance-3" "instance-4" "instance-5" "instance-6" "instance-7" "instance-8")

for instance in "${INSTANCES[@]}"; do
    log "Testing VNC proxy for $instance..."
    
    # Test WebSocket endpoint
    WS_URL="ws://127.0.0.1:$FRONTEND_PORT/proxy/vnc/$instance/"
    log "WebSocket URL: $WS_URL"
    
    # Try to connect using netcat or telnet to test port connectivity
    if nc -z -w5 127.0.0.1 "$FRONTEND_PORT" 2>/dev/null; then
        success "Port $FRONTEND_PORT is open for $instance"
    else
        error "Port $FRONTEND_PORT is not accessible for $instance"
    fi
    
    # Test HTTP endpoint (should return 404 for WebSocket upgrade)
    HTTP_URL="http://127.0.0.1:$FRONTEND_PORT/proxy/vnc/$instance/"
    HTTP_RESPONSE=$(curl -s -w "%{http_code}" "$HTTP_URL" -o /dev/null 2>/dev/null || echo "000")
    
    if [ "$HTTP_RESPONSE" = "404" ] || [ "$HTTP_RESPONSE" = "400" ]; then
        success "HTTP endpoint responds for $instance (status: $HTTP_RESPONSE)"
    else
        warning "HTTP endpoint for $instance returned status: $HTTP_RESPONSE"
    fi
    
    echo "Instance: $instance, WS_URL: $WS_URL, HTTP_STATUS: $HTTP_RESPONSE" >> "$REPORT_FILE"
done

# Check emulator pod status
log "Checking emulator pod status..."
EMULATOR_PODS=$(kubectl get pods -n loco -l app=loco-loco-emulator -o name 2>/dev/null || echo "")
if [ -n "$EMULATOR_PODS" ]; then
    success "Found emulator pods:"
    echo "$EMULATOR_PODS" | tee -a "$REPORT_FILE"
    
    for pod in $EMULATOR_PODS; do
        POD_STATUS=$(kubectl get "$pod" -n loco -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        POD_READY=$(kubectl get "$pod" -n loco -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "Unknown")
        log "Pod $pod: Status=$POD_STATUS, Ready=$POD_READY"
        echo "Pod: $pod, Status: $POD_STATUS, Ready: $POD_READY" >> "$REPORT_FILE"
    done
else
    warning "No emulator pods found"
fi

# Test backend connectivity
log "Testing backend connectivity..."
BACKEND_POD=$(kubectl get pods -n loco -l app=loco-loco-backend -o name 2>/dev/null | head -1)
if [ -n "$BACKEND_POD" ]; then
    success "Found backend pod: $BACKEND_POD"
    
    # Test backend health endpoint
    if kubectl exec -n loco "$BACKEND_POD" -- wget -qO- http://localhost:3001/health 2>/dev/null; then
        success "Backend health check passed"
    else
        error "Backend health check failed"
    fi
else
    error "No backend pod found"
fi

# Generate summary
log "Generating test summary..."
echo "" >> "$REPORT_FILE"
echo "=== Test Summary ===" >> "$REPORT_FILE"
echo "Frontend URL: $FRONTEND_URL" >> "$REPORT_FILE"
echo "Frontend Port: $FRONTEND_PORT" >> "$REPORT_FILE"
echo "Backend Pod: $BACKEND_POD" >> "$REPORT_FILE"
echo "Emulator Pods: $EMULATOR_PODS" >> "$REPORT_FILE"

# Create HTML report
HTML_REPORT="${SCREENSHOT_DIR}/vnc-test-report-${TIMESTAMP}.html"
cat > "$HTML_REPORT" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>VNC Cluster Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .success { color: #28a745; }
        .error { color: #dc3545; }
        .warning { color: #ffc107; }
        pre { background: #f8f9fa; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>VNC Cluster Test Report</h1>
        <p>Generated: $(date)</p>
        <p>Frontend URL: $FRONTEND_URL</p>
    </div>
    
    <h2>Test Results</h2>
    <pre>$(cat "$REPORT_FILE")</pre>
</body>
</html>
EOF

success "Test completed!"
log "Report saved to: $REPORT_FILE"
log "HTML report saved to: $HTML_REPORT"

echo ""
echo "=== VNC Cluster Test Summary ==="
echo "Frontend URL: $FRONTEND_URL"
echo "Report: $REPORT_FILE"
echo "HTML Report: $HTML_REPORT"
echo ""
echo "To view the frontend, open: $FRONTEND_URL"
echo "To test VNC connections manually, use the WebSocket URLs shown above" 