#!/bin/bash
# Simple backend-only deployment script to isolate and fix the API issue

set -e

# Configuration
IMAGE_NAME="loco-backend"
IMAGE_TAG="latest"
NAMESPACE="loco"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}==== $1 ====${NC}"
}

# Build and deploy backend only
deploy_backend_simple() {
    log_section "Simple Backend Deployment"
    
    # Build image
    log_info "Building backend image..."
    cd backend
    docker build --no-cache -t "${IMAGE_NAME}:${IMAGE_TAG}" .
    cd ..
    
    # Load into minikube
    log_info "Loading image into minikube..."
    minikube image load "${IMAGE_NAME}:${IMAGE_TAG}"
    
    # Create namespace
    log_info "Creating namespace..."
    kubectl create namespace "$NAMESPACE" || echo "Namespace exists"
    
    # Create simple backend deployment
    log_info "Creating backend deployment..."
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loco-backend
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: loco-backend
  template:
    metadata:
      labels:
        app: loco-backend
        app.kubernetes.io/component: backend
    spec:
      serviceAccountName: loco-backend-sa
      containers:
      - name: backend
        image: ${IMAGE_NAME}:${IMAGE_TAG}
        imagePullPolicy: Always
        ports:
        - containerPort: 3001
        env:
        - name: NODE_ENV
          value: "production"
        - name: ALLOW_EMPTY_DISCOVERY
          value: "false"
        - name: FORCE_CONSOLE_LOGGING
          value: "true"
        - name: LOG_LEVEL
          value: "debug"
        - name: KUBERNETES_NAMESPACE
          value: "${NAMESPACE}"
---
apiVersion: v1
kind: Service
metadata:
  name: loco-backend
  namespace: ${NAMESPACE}
spec:
  selector:
    app: loco-backend
  ports:
  - port: 3001
    targetPort: 3001
  type: ClusterIP
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: loco-backend-sa
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: loco-backend-cluster-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["statefulsets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: loco-backend-cluster-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: loco-backend-cluster-role
subjects:
- kind: ServiceAccount
  name: loco-backend-sa
  namespace: ${NAMESPACE}
EOF
    
    # Wait for deployment
    log_info "Waiting for backend to be ready..."
    kubectl wait --for=condition=available deployment/loco-backend -n "$NAMESPACE" --timeout=300s
    
    log_success "Backend deployed successfully!"
}

# Test and debug
test_backend() {
    log_section "Testing Backend"
    
    # Show pod status
    log_info "Pod status:"
    kubectl get pods -n "$NAMESPACE" -l app=loco-backend
    
    # Show logs
    log_info "Backend logs:"
    BACKEND_POD=$(kubectl get pods -n "$NAMESPACE" -l app=loco-backend -o jsonpath='{.items[0].metadata.name}')
    kubectl logs "$BACKEND_POD" -n "$NAMESPACE" --tail=30
    
    # Check for API error
    log_info "Checking for API parameter error..."
    if kubectl logs "$BACKEND_POD" -n "$NAMESPACE" | grep -q "Required parameter namespace was null or undefined"; then
        log_error "❌ API parameter error still present!"
        
        # Show file in container to verify it matches source
        log_info "Checking file in running container:"
        kubectl exec "$BACKEND_POD" -n "$NAMESPACE" -- grep -n "await this.k8sApi" /app/services/kubernetesDiscovery.js
        
        return 1
    else
        log_success "✅ No API parameter error found!"
        return 0
    fi
}

# Port forward for testing
test_api() {
    log_section "Testing API"
    
    log_info "Port forwarding backend service..."
    kubectl port-forward -n "$NAMESPACE" service/loco-backend 3001:3001 &
    PORT_FORWARD_PID=$!
    sleep 5
    
    # Test endpoints
    log_info "Testing health endpoint..."
    if curl -f http://localhost:3001/health 2>/dev/null; then
        log_success "✅ Health endpoint working"
    else
        log_error "❌ Health endpoint failed"
    fi
    
    log_info "Testing instances endpoint..."
    curl -s http://localhost:3001/api/instances | head -10
    
    # Cleanup
    kill $PORT_FORWARD_PID 2>/dev/null || true
}

# Main execution
main() {
    log_section "Simple Backend Deployment Script"
    
    deploy_backend_simple
    test_backend
    
    if [ $? -eq 0 ]; then
        test_api
        log_success "🎯 Backend deployment and testing completed successfully!"
    else
        log_error "❌ Backend still has API issues - need further investigation"
        exit 1
    fi
}

main "$@"
