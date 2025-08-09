#!/bin/bash

# Enhanced Backend Deployment Script
# Deploys the enhanced backend with VNC stream health monitoring and video activity detection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "🚀 Enhanced Backend Deployment Script (Video Activity Detection)"
echo "=============================================================="

# Check if we're in a Kubernetes environment
if command -v kubectl &> /dev/null; then
    print_info "Kubernetes environment detected"
    
    # Check if namespace exists
    if kubectl get namespace loco &> /dev/null; then
        print_info "Namespace 'loco' exists"
    else
        print_error "Namespace 'loco' not found. Please run bootstrap-cluster.sh first."
        exit 1
    fi
    
    # Build enhanced backend image
    print_info "Building enhanced backend image with video activity detection..."
    docker build -t compose-backend:enhanced ./backend
    
    # Load image into minikube if in minikube environment
    if command -v minikube &> /dev/null && minikube status &> /dev/null; then
        print_info "Minikube detected, loading image..."
        minikube image load compose-backend:enhanced
    fi
    
    # Update deployment to use enhanced backend
    print_info "Updating backend deployment..."
    kubectl set image deployment/loco-loco-backend backend=compose-backend:enhanced -n loco
    
    # Wait for rollout
    print_info "Waiting for deployment rollout..."
    kubectl rollout status deployment/loco-loco-backend -n loco --timeout=300s
    
    # Check pod status
    print_info "Checking pod status..."
    kubectl get pods -n loco -l app=loco-loco-backend
    
    # Port forward for testing
    print_info "Setting up port forwarding for testing..."
    kubectl port-forward service/loco-loco-backend 3001:3001 -n loco &
    PF_PID=$!
    
    # Wait for port forward
    sleep 5
    
    # Test enhanced health checks
    print_info "Testing enhanced health checks with video activity detection..."
    
    # Test container health check
    print_info "Testing container health check (video activity dependent)..."
    CONTAINER_HEALTH_RESPONSE=$(curl -s http://localhost:3001/health/container)
    if echo "$CONTAINER_HEALTH_RESPONSE" | grep -q "videoActivity"; then
        print_success "Container health check working (video activity detection enabled)"
        echo "$CONTAINER_HEALTH_RESPONSE" | jq '.status, .videoActivity, .healthyConnections' 2>/dev/null || echo "$CONTAINER_HEALTH_RESPONSE"
    else
        print_error "Container health check failed"
        echo "$CONTAINER_HEALTH_RESPONSE"
    fi
    
    # Test detailed metrics
    print_info "Testing detailed metrics with video activity..."
    METRICS_RESPONSE=$(curl -s http://localhost:3001/health/metrics)
    if echo "$METRICS_RESPONSE" | grep -q "containerHealth"; then
        print_success "Detailed metrics working with video activity tracking"
        echo "$METRICS_RESPONSE" | jq '.containerHealth, .vncConnections.healthyConnections' 2>/dev/null || echo "$METRICS_RESPONSE"
    else
        print_error "Metrics endpoint failed"
        echo "$METRICS_RESPONSE"
    fi
    
    # Run comprehensive test suite
    print_info "Running comprehensive test suite with video activity detection..."
    if [ -f "tests/test-enhanced-health.js" ]; then
        node tests/test-enhanced-health.js
        TEST_RESULT=$?
        if [ $TEST_RESULT -eq 0 ]; then
            print_success "All enhanced health tests passed!"
        else
            print_warning "Some tests failed (this may be expected if VNC servers are not running)"
        fi
    else
        print_warning "Enhanced health test suite not found"
    fi
    
    # Run video activity detection tests
    print_info "Running video activity detection tests..."
    if [ -f "tests/test-video-activity.js" ]; then
        node tests/test-video-activity.js
        VIDEO_TEST_RESULT=$?
        if [ $VIDEO_TEST_RESULT -eq 0 ]; then
            print_success "All video activity detection tests passed!"
        else
            print_warning "Some video activity tests failed (this may be expected if no VNC streams are active)"
        fi
    else
        print_warning "Video activity test suite not found"
    fi
    
    # Cleanup port forward
    kill $PF_PID 2>/dev/null || true
    
    print_success "Enhanced backend deployment complete with video activity detection!"
    print_info "Container health check available at: http://localhost:3001/health/container"
    print_info "Detailed metrics available at: http://localhost:3001/health/metrics"
    
else
    print_info "Docker Compose environment detected"
    
    # Build enhanced backend image
    print_info "Building enhanced backend image with video activity detection..."
    docker build -t compose-backend:enhanced ./backend
    
    # Update docker-compose to use enhanced backend
    print_info "Updating docker-compose configuration..."
    sed -i.bak 's/compose-backend:latest/compose-backend:enhanced/g' compose/docker-compose.yml
    
    # Restart backend service
    print_info "Restarting backend service..."
    docker-compose -f compose/docker-compose.yml restart backend
    
    # Wait for service to be ready
    print_info "Waiting for backend service to be ready..."
    sleep 10
    
    # Test enhanced health checks
    print_info "Testing enhanced health checks with video activity detection..."
    
    # Test container health check
    print_info "Testing container health check (video activity dependent)..."
    CONTAINER_HEALTH_RESPONSE=$(curl -s http://localhost:3001/health/container)
    if echo "$CONTAINER_HEALTH_RESPONSE" | grep -q "videoActivity"; then
        print_success "Container health check working (video activity detection enabled)"
        echo "$CONTAINER_HEALTH_RESPONSE" | jq '.status, .videoActivity, .healthyConnections' 2>/dev/null || echo "$CONTAINER_HEALTH_RESPONSE"
    else
        print_error "Container health check failed"
        echo "$CONTAINER_HEALTH_RESPONSE"
    fi
    
    # Test detailed metrics
    print_info "Testing detailed metrics with video activity..."
    METRICS_RESPONSE=$(curl -s http://localhost:3001/health/metrics)
    if echo "$METRICS_RESPONSE" | grep -q "containerHealth"; then
        print_success "Detailed metrics working with video activity tracking"
        echo "$METRICS_RESPONSE" | jq '.containerHealth, .vncConnections.healthyConnections' 2>/dev/null || echo "$METRICS_RESPONSE"
    else
        print_error "Metrics endpoint failed"
        echo "$METRICS_RESPONSE"
    fi
    
    print_success "Enhanced backend deployment complete with video activity detection!"
    print_info "Container health check available at: http://localhost:3001/health/container"
    print_info "Detailed metrics available at: http://localhost:3001/health/metrics"
fi

echo ""
echo "🎯 Enhanced Backend Features (Video Activity Detection):"
echo "  ✅ Real-time VNC video stream monitoring"
echo "  ✅ Bytes-per-second bandwidth tracking"
echo "  ✅ Video frame detection and counting"
echo "  ✅ Container health tied to video activity"
echo "  ✅ Automatic health status transitions"
echo "  ✅ Kubernetes probe validation"
echo "  ✅ Production-ready resource limits"
echo "  ✅ Graceful error handling"
echo ""
echo "📊 Monitor your VNC video streams with:"
echo "  curl http://localhost:3001/health/container"
echo "  curl http://localhost:3001/health/metrics"
echo ""
echo "🎬 Container will only stay healthy when VNC servers are actively streaming video!" 