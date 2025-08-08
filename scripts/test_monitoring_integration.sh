#!/usr/bin/env bash
# Test script for comprehensive QEMU health monitoring and auto-discovery
set -euo pipefail

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-loco-test}
NAMESPACE=${NAMESPACE:-loco}
TIMEOUT=${TIMEOUT:-300}
LOG_DIR="k8s-tests/logs"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/monitoring-integration.log") 2>&1

echo "🧪 Testing QEMU Health Monitoring and Auto-Discovery Integration" && date

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

# Function to check QEMU health endpoints
check_qemu_health() {
    local instance_name="$1"
    echo "🔍 Checking QEMU health for $instance_name"
    
    # Port-forward to health endpoint
    kubectl port-forward -n "$NAMESPACE" "pod/$instance_name" 8080:8080 &
    local pf_pid=$!
    sleep 3
    
    # Test health endpoint
    local health_response
    if health_response=$(curl -s http://localhost:8080/health 2>/dev/null); then
        echo "✅ Health endpoint accessible: $health_response"
        
        # Check specific health metrics
        if echo "$health_response" | grep -q "qemu_healthy.*true"; then
            echo "✅ QEMU process healthy"
        else
            echo "⚠️  QEMU process issues detected"
        fi
        
        if echo "$health_response" | grep -q "vnc_available.*true"; then
            echo "✅ VNC available"
        else
            echo "⚠️  VNC not available"
        fi
        
        if echo "$health_response" | grep -q "pulse_running.*true"; then
            echo "✅ Audio subsystem healthy"
        else
            echo "⚠️  Audio subsystem issues"
        fi
        
    else
        echo "❌ Health endpoint not accessible"
    fi
    
    # Clean up port-forward
    kill $pf_pid || true
    wait $pf_pid 2>/dev/null || true
}

# Function to test backend auto-discovery
test_auto_discovery() {
    echo "🔍 Testing Kubernetes auto-discovery"
    
    # Port-forward to backend
    kubectl port-forward -n "$NAMESPACE" service/loco-backend 3000:3000 &
    local pf_pid=$!
    sleep 3
    
    # Test discovery endpoint
    local discovery_response
    if discovery_response=$(curl -s http://localhost:3000/api/instances/discovery-info 2>/dev/null); then
        echo "✅ Discovery endpoint accessible"
        echo "Discovery response: $discovery_response"
        
        if echo "$discovery_response" | grep -q '"discoveryEnabled":true'; then
            echo "✅ Auto-discovery enabled"
        else
            echo "⚠️  Auto-discovery not enabled"
        fi
        
        if echo "$discovery_response" | grep -q '"namespace":"'$NAMESPACE'"'; then
            echo "✅ Correct namespace detected: $NAMESPACE"
        else
            echo "⚠️  Namespace detection issue"
        fi
    else
        echo "❌ Discovery endpoint not accessible"
    fi
    
    # Test instances endpoint
    local instances_response
    if instances_response=$(curl -s http://localhost:3000/api/instances 2>/dev/null); then
        echo "✅ Instances endpoint accessible"
        local instance_count
        instance_count=$(echo "$instances_response" | jq '. | length' 2>/dev/null || echo "0")
        echo "Discovered instances: $instance_count"
        
        if [ "$instance_count" -gt 0 ]; then
            echo "✅ Instances auto-discovered successfully"
        else
            echo "⚠️  No instances discovered"
        fi
    else
        echo "❌ Instances endpoint not accessible"
    fi
    
    # Test deep health endpoint
    local health_response
    if health_response=$(curl -s http://localhost:3000/api/quality/deep-health 2>/dev/null); then
        echo "✅ Deep health endpoint accessible"
        echo "Health response preview: $(echo "$health_response" | jq -r 'keys[]' 2>/dev/null | head -3)"
    else
        echo "⚠️  Deep health endpoint not accessible"
    fi
    
    # Clean up port-forward
    kill $pf_pid || true
    wait $pf_pid 2>/dev/null || true
}

# Main test execution
main() {
    echo "🚀 Starting monitoring integration test" && date
    
    # Check if cluster exists
    if ! kubectl cluster-info &>/dev/null; then
        echo "❌ No Kubernetes cluster accessible"
        exit 1
    fi
    
    echo "✅ Kubernetes cluster accessible"
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        echo "📦 Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
    fi
    
    # Deploy the Helm chart with monitoring enabled
    echo "📦 Deploying Lego Loco cluster with monitoring"
    helm upgrade --install loco ./helm/loco-chart \
        --namespace "$NAMESPACE" \
        --set replicas=2 \
        --set rbac.create=true \
        --set emulator.image=ghcr.io/mroie/qemu-softgpu \
        --set emulator.tag=latest \
        --set backend.image=ghcr.io/mroie/lego-loco-backend \
        --set backend.tag=latest \
        --set frontend.image=ghcr.io/mroie/lego-loco-frontend \
        --set frontend.tag=latest \
        --wait --timeout=300s
    
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
    
    echo "✅ All pods are ready"
    
    # Show pod status
    echo "📊 Current pod status:"
    kubectl get pods -n "$NAMESPACE" -o wide
    
    # Test RBAC permissions
    echo "🔐 Testing RBAC permissions"
    kubectl auth can-i list pods --as=system:serviceaccount:$NAMESPACE:loco-backend -n "$NAMESPACE"
    kubectl auth can-i list services --as=system:serviceaccount:$NAMESPACE:loco-backend -n "$NAMESPACE"
    kubectl auth can-i get statefulsets --as=system:serviceaccount:$NAMESPACE:loco-backend -n "$NAMESPACE"
    
    # Test QEMU health endpoints for each emulator
    echo "🩺 Testing QEMU health endpoints"
    local emulator_pods
    emulator_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=emulator -o name | sed 's/pod\///')
    
    for pod in $emulator_pods; do
        check_qemu_health "$pod"
    done
    
    # Test backend auto-discovery
    test_auto_discovery
    
    # Test recovery functionality
    echo "🔄 Testing recovery functionality"
    local first_pod
    first_pod=$(echo "$emulator_pods" | head -1)
    
    # Port-forward to backend for recovery test
    kubectl port-forward -n "$NAMESPACE" service/loco-backend 3000:3000 &
    local pf_pid=$!
    sleep 3
    
    if recovery_response=$(curl -s -X POST "http://localhost:3000/api/quality/recover/$first_pod" 2>/dev/null); then
        echo "✅ Recovery endpoint accessible"
        echo "Recovery response: $recovery_response"
    else
        echo "⚠️  Recovery endpoint not accessible"
    fi
    
    # Clean up port-forward
    kill $pf_pid || true
    wait $pf_pid 2>/dev/null || true
    
    echo "🎉 Monitoring integration test completed successfully" && date
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