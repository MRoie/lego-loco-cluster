#!/usr/bin/env bash
# Test script for comprehensive QEMU monitoring with real container deployment and UI verification
set -euo pipefail

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-loco-test}
NAMESPACE=${NAMESPACE:-loco}
TIMEOUT=${TIMEOUT:-600}
LOG_DIR="k8s-tests/logs"
BUILD_CONTAINERS=${BUILD_CONTAINERS:-true}

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/comprehensive-monitoring-test.log") 2>&1

echo "🧪 Comprehensive QEMU Monitoring Integration Test with Real Containers" && date

# Function to wait for condition
wait_for_condition() {
    local condition="$1"
    local description="$2"
    local timeout="${3:-60}"
    
    echo "⏳ Waiting for: $description"
    local count=0
    while ! eval "$condition" && [ $count -lt $timeout ]; do
        sleep 2
        ((count += 2))
        if [ $((count % 10)) -eq 0 ]; then
            echo "   ... still waiting ($count/$timeout seconds)"
        fi
    done
    
    if [ $count -ge $timeout ]; then
        echo "❌ Timeout waiting for: $description"
        return 1
    fi
    
    echo "✅ Success: $description"
    return 0
}

# Function to build and load container images
build_and_load_containers() {
    echo "🔨 Building and loading container images"
    
    # Build qemu-softgpu container
    echo "Building qemu-softgpu container..."
    cd containers/qemu-softgpu
    if ! docker build -t loco-qemu-softgpu:test .; then
        echo "❌ Failed to build qemu-softgpu container"
        exit 1
    fi
    if ! minikube image load loco-qemu-softgpu:test; then
        echo "❌ Failed to load qemu-softgpu container into minikube"
        exit 1
    fi
    cd ../..
    
    # Build backend container
    echo "Building backend container..."
    cd backend
    if ! docker build -t loco-backend:test .; then
        echo "❌ Failed to build backend container"
        exit 1
    fi
    if ! minikube image load loco-backend:test; then
        echo "❌ Failed to load backend container into minikube"
        exit 1
    fi
    cd ..
    
    # Build frontend container
    echo "Building frontend container..."
    cd frontend
    if ! docker build -t loco-frontend:test .; then
        echo "❌ Failed to build frontend container"
        exit 1
    fi
    if ! minikube image load loco-frontend:test; then
        echo "❌ Failed to load frontend container into minikube"
        exit 1
    fi
    cd ..
    
    echo "✅ Container images built and loaded into minikube"
    
    # Verify images are loaded
    echo "📋 Verifying loaded images in minikube:"
    minikube image ls | grep loco || echo "⚠️  No loco images found in minikube"
}

# Function to check real QEMU health endpoints
check_real_qemu_health() {
    local instance_name="$1"
    echo "🔍 Checking Real QEMU Health for $instance_name"
    
    # Port-forward to health endpoint
    kubectl port-forward -n "$NAMESPACE" "pod/$instance_name" 8080:8080 &
    local pf_pid=$!
    sleep 5
    
    # Test health endpoint with retries
    local health_response=""
    local attempts=0
    local max_attempts=10
    
    while [ $attempts -lt $max_attempts ]; do
        if health_response=$(curl -s http://localhost:8080/health 2>/dev/null); then
            break
        fi
        ((attempts++))
        echo "   Attempt $attempts/$max_attempts failed, retrying..."
        sleep 3
    done
    
    if [ $attempts -eq $max_attempts ]; then
        echo "❌ Health endpoint not accessible after $max_attempts attempts"
        kill $pf_pid || true
        return 1
    fi
    
    echo "✅ Health endpoint accessible"
    echo "Raw health response: $health_response"
    
    # Validate health response structure
    if echo "$health_response" | jq . >/dev/null 2>&1; then
        echo "✅ Valid JSON response"
        
        # Check specific health metrics
        local qemu_healthy=$(echo "$health_response" | jq -r '.qemu_healthy // false')
        local overall_status=$(echo "$health_response" | jq -r '.overall_status // "unknown"')
        local vnc_available=$(echo "$health_response" | jq -r '.video.vnc_available // false')
        local pulse_running=$(echo "$health_response" | jq -r '.audio.pulse_running // false')
        
        echo "QEMU Health: $qemu_healthy"
        echo "Overall Status: $overall_status"
        echo "VNC Available: $vnc_available"
        echo "Audio Running: $pulse_running"
        
        # Validate expected health components exist
        local has_video=$(echo "$health_response" | jq -r 'has("video")')
        local has_audio=$(echo "$health_response" | jq -r 'has("audio")')
        local has_performance=$(echo "$health_response" | jq -r 'has("performance")')
        local has_network=$(echo "$health_response" | jq -r 'has("network")')
        
        if [ "$has_video" = "true" ] && [ "$has_audio" = "true" ] && [ "$has_performance" = "true" ] && [ "$has_network" = "true" ]; then
            echo "✅ All health components present"
        else
            echo "⚠️  Missing health components: video=$has_video, audio=$has_audio, performance=$has_performance, network=$has_network"
        fi
        
    else
        echo "❌ Invalid JSON response"
    fi
    
    # Clean up port-forward
    kill $pf_pid || true
    wait $pf_pid 2>/dev/null || true
}

# Function to test backend monitoring API integration
test_backend_monitoring_api() {
    echo "🔍 Testing Backend Monitoring API Integration"
    
    # Port-forward to backend
    kubectl port-forward -n "$NAMESPACE" service/loco-backend 3000:3000 &
    local pf_pid=$!
    sleep 5
    
    echo "Testing discovery endpoint..."
    local discovery_response
    if discovery_response=$(curl -s http://localhost:3000/api/instances/discovery-info 2>/dev/null); then
        echo "✅ Discovery endpoint accessible"
        echo "Discovery response: $discovery_response"
        
        # Validate discovery response
        local discovery_enabled=$(echo "$discovery_response" | jq -r '.discoveryEnabled // false')
        local namespace=$(echo "$discovery_response" | jq -r '.namespace // ""')
        
        echo "Discovery Enabled: $discovery_enabled"
        echo "Detected Namespace: $namespace"
        
        if [ "$discovery_enabled" = "true" ] && [ "$namespace" = "$NAMESPACE" ]; then
            echo "✅ Auto-discovery working correctly"
        else
            echo "⚠️  Auto-discovery configuration issue"
        fi
    else
        echo "❌ Discovery endpoint not accessible"
    fi
    
    echo "Testing instances endpoint..."
    local instances_response
    if instances_response=$(curl -s http://localhost:3000/api/instances 2>/dev/null); then
        echo "✅ Instances endpoint accessible"
        local instance_count=$(echo "$instances_response" | jq '. | length' 2>/dev/null || echo "0")
        echo "Discovered instances: $instance_count"
        
        if [ "$instance_count" -gt 0 ]; then
            echo "✅ Instances auto-discovered successfully"
            echo "Instance details: $(echo "$instances_response" | jq -r '.[].instanceId' | head -3)"
        else
            echo "⚠️  No instances discovered"
        fi
    else
        echo "❌ Instances endpoint not accessible"
    fi
    
    echo "Testing deep health endpoint..."
    local deep_health_response
    if deep_health_response=$(curl -s http://localhost:3000/api/quality/deep-health 2>/dev/null); then
        echo "✅ Deep health endpoint accessible"
        echo "Deep health preview: $(echo "$deep_health_response" | jq 'keys[]' 2>/dev/null | head -3)"
        
        # Validate deep health structure
        local health_keys=$(echo "$deep_health_response" | jq -r 'keys[]' 2>/dev/null)
        if echo "$health_keys" | grep -q "instance"; then
            echo "✅ Deep health contains instance data"
        else
            echo "⚠️  Deep health missing instance data"
        fi
    else
        echo "⚠️  Deep health endpoint not accessible"
    fi
    
    echo "Testing recovery endpoint..."
    local first_instance=$(echo "$instances_response" | jq -r '.[0].instanceId // "loco-emulator-0"' 2>/dev/null)
    if [ -n "$first_instance" ]; then
        local recovery_response
        if recovery_response=$(curl -s -X POST "http://localhost:3000/api/quality/recover/$first_instance" 2>/dev/null); then
            echo "✅ Recovery endpoint accessible"
            echo "Recovery response: $recovery_response"
        else
            echo "⚠️  Recovery endpoint not accessible"
        fi
    fi
    
    # Clean up port-forward
    kill $pf_pid || true
    wait $pf_pid 2>/dev/null || true
}

# Function to test frontend UI integration
test_frontend_ui_integration() {
    echo "🖥️  Testing Frontend UI Integration"
    
    # Port-forward to frontend
    kubectl port-forward -n "$NAMESPACE" service/loco-frontend 8080:80 &
    local pf_pid=$!
    sleep 5
    
    echo "Testing frontend accessibility..."
    local frontend_response
    if frontend_response=$(curl -s http://localhost:8080/ 2>/dev/null); then
        echo "✅ Frontend accessible"
        
        # Check if frontend contains monitoring-related content
        if echo "$frontend_response" | grep -q "quality\|monitoring\|health"; then
            echo "✅ Frontend contains monitoring UI elements"
        else
            echo "⚠️  Frontend may be missing monitoring UI"
        fi
        
        # Check for static assets
        if curl -s http://localhost:8080/static/js/ 2>/dev/null | grep -q ".js"; then
            echo "✅ Frontend JavaScript assets accessible"
        else
            echo "⚠️  Frontend assets may not be loading"
        fi
        
    else
        echo "❌ Frontend not accessible"
    fi
    
    # Test API proxy from frontend
    echo "Testing frontend API proxy..."
    if curl -s http://localhost:8080/api/instances 2>/dev/null | jq . >/dev/null 2>&1; then
        echo "✅ Frontend API proxy working"
    else
        echo "⚠️  Frontend API proxy not working"
    fi
    
    # Clean up port-forward
    kill $pf_pid || true
    wait $pf_pid 2>/dev/null || true
}

# Function to test complete monitoring pipeline
test_complete_monitoring_pipeline() {
    echo "🔄 Testing Complete Monitoring Pipeline"
    
    # Start multiple port-forwards for end-to-end testing
    kubectl port-forward -n "$NAMESPACE" service/loco-backend 3001:3000 &
    local backend_pf=$!
    
    kubectl port-forward -n "$NAMESPACE" service/loco-frontend 8081:80 &
    local frontend_pf=$!
    
    sleep 5
    
    echo "Testing end-to-end monitoring data flow..."
    
    # Get instances from backend
    local instances_data
    if instances_data=$(curl -s http://localhost:3001/api/instances 2>/dev/null); then
        local instance_count=$(echo "$instances_data" | jq '. | length' 2>/dev/null || echo "0")
        echo "Backend reports $instance_count instances"
        
        if [ "$instance_count" -gt 0 ]; then
            # Test deep health for first instance
            local first_instance=$(echo "$instances_data" | jq -r '.[0].instanceId')
            echo "Testing deep health for: $first_instance"
            
            if curl -s "http://localhost:3001/api/quality/deep-health/$first_instance" | jq . >/dev/null 2>&1; then
                echo "✅ Individual instance deep health working"
            fi
            
            # Test that frontend can access the same data
            if curl -s "http://localhost:8081/api/instances" | jq . >/dev/null 2>&1; then
                echo "✅ Frontend can access backend instance data"
                
                if curl -s "http://localhost:8081/api/quality/deep-health" | jq . >/dev/null 2>&1; then
                    echo "✅ Frontend can access monitoring data"
                else
                    echo "⚠️  Frontend cannot access monitoring data"
                fi
            else
                echo "⚠️  Frontend cannot access backend data"
            fi
        fi
    fi
    
    # Clean up port-forwards
    kill $backend_pf $frontend_pf || true
    wait $backend_pf $frontend_pf 2>/dev/null || true
}

# Function to test RBAC and permissions
test_rbac_permissions() {
    echo "🔐 Testing RBAC Permissions"
    
    # Test service account permissions
    kubectl auth can-i list pods --as=system:serviceaccount:$NAMESPACE:loco-backend -n "$NAMESPACE"
    kubectl auth can-i list services --as=system:serviceaccount:$NAMESPACE:loco-backend -n "$NAMESPACE"
    kubectl auth can-i get statefulsets --as=system:serviceaccount:$NAMESPACE:loco-backend -n "$NAMESPACE"
    
    # Test if backend can actually perform discovery
    local backend_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=backend -o name | head -1)
    if [ -n "$backend_pod" ]; then
        echo "Testing auto-discovery from backend pod..."
        if kubectl exec -n "$NAMESPACE" "$backend_pod" -- curl -s http://localhost:3000/api/instances/discovery-info | grep -q "discoveryEnabled"; then
            echo "✅ Backend auto-discovery functional"
        else
            echo "⚠️  Backend auto-discovery not working"
        fi
    fi
}

# Main test execution
main() {
    echo "🚀 Starting Comprehensive Monitoring Integration Test" && date
    
    # Check if cluster exists
    if ! kubectl cluster-info &>/dev/null; then
        echo "❌ No Kubernetes cluster accessible"
        exit 1
    fi
    
    echo "✅ Kubernetes cluster accessible"
    kubectl cluster-info
    
    # Build and load containers if requested
    if [ "$BUILD_CONTAINERS" = "true" ]; then
        build_and_load_containers
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        echo "📦 Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
    fi
    
    # Deploy the Helm chart with monitoring enabled and test images
    echo "📦 Deploying Lego Loco cluster with test containers and monitoring"
    
    # First check if helm chart exists
    if [ ! -d "./helm/loco-chart" ]; then
        echo "❌ Helm chart not found at ./helm/loco-chart"
        exit 1
    fi
    
    if ! helm upgrade --install loco ./helm/loco-chart \
        --namespace "$NAMESPACE" \
        --set replicas=2 \
        --set rbac.create=true \
        --set emulator.image=loco-qemu-softgpu \
        --set emulator.tag=test \
        --set emulator.imagePullPolicy=Never \
        --set backend.image=loco-backend \
        --set backend.tag=test \
        --set backend.imagePullPolicy=Never \
        --set frontend.image=loco-frontend \
        --set frontend.tag=test \
        --set frontend.imagePullPolicy=Never \
        --wait --timeout=600s; then
        
        echo "❌ Helm deployment failed"
        echo "📋 Checking pod status for debugging:"
        kubectl get pods -n "$NAMESPACE" -o wide || true
        echo "📋 Checking events for debugging:"
        kubectl get events -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp || true
        exit 1
    fi
    
    echo "✅ Helm deployment completed"
    
    # Wait for pods to be ready
    echo "⏳ Waiting for pods to be ready"
    wait_for_condition \
        "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/part-of=lego-loco-cluster --no-headers | grep -v Running | wc -l | grep -q '^0$'" \
        "All pods running" \
        $TIMEOUT
    
    # Wait specifically for emulator pods
    wait_for_condition \
        "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=emulator --no-headers | grep Running | wc -l | grep -q '^2$'" \
        "Emulator pods ready" \
        $TIMEOUT
    
    # Wait for backend pod
    wait_for_condition \
        "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=backend --no-headers | grep Running | wc -l | grep -q '^1$'" \
        "Backend pod ready" \
        $TIMEOUT
    
    # Wait for frontend pod
    wait_for_condition \
        "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=frontend --no-headers | grep Running | wc -l | grep -q '^1$'" \
        "Frontend pod ready" \
        $TIMEOUT
    
    echo "✅ All pods are ready"
    
    # Show detailed pod status
    echo "📊 Current pod status:"
    kubectl get pods -n "$NAMESPACE" -o wide
    kubectl describe pods -n "$NAMESPACE"
    
    # Test RBAC permissions
    test_rbac_permissions
    
    # Test real QEMU health endpoints for each emulator
    echo "🩺 Testing Real QEMU Health Endpoints"
    local emulator_pods
    emulator_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=emulator -o name | sed 's/pod\///')
    
    for pod in $emulator_pods; do
        check_real_qemu_health "$pod"
    done
    
    # Test backend monitoring API integration
    test_backend_monitoring_api
    
    # Test frontend UI integration
    test_frontend_ui_integration
    
    # Test complete monitoring pipeline
    test_complete_monitoring_pipeline
    
    echo "🎉 Comprehensive Monitoring Integration Test Completed" && date
}

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up test resources"
    
    # Kill any remaining port-forwards
    pkill -f "kubectl port-forward" || true
    
    # Optionally remove the test deployment
    if [ "${CLEANUP:-false}" = "true" ]; then
        helm uninstall loco -n "$NAMESPACE" || true
        kubectl delete namespace "$NAMESPACE" || true
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Run main test
main "$@"