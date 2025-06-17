#!/bin/bash

set -e  # Exit on any error

echo "🔄 Starting full cluster rebuild and deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $1"
}

# Step 1: Kill all Vite processes
print_status "Killing all Vite processes..."
pkill -f vite || true
print_success "Vite processes terminated"

# Step 2: Build frontend image
print_status "Building frontend image..."
cd /workspaces/lego-loco-cluster/frontend
docker build -t localhost:5000/lego-loco-frontend:latest .
if [ $? -eq 0 ]; then
    print_success "Frontend image built successfully"
else
    print_error "Frontend build failed"
    exit 1
fi

# Step 3: Build backend image
print_status "Building backend image..."
cd /workspaces/lego-loco-cluster/backend
docker build -t localhost:5000/lego-loco-backend:latest .
if [ $? -eq 0 ]; then
    print_success "Backend image built successfully"
else
    print_error "Backend build failed"
    exit 1
fi

# Step 4: Build QEMU image
print_status "Building QEMU image..."
cd /workspaces/lego-loco-cluster/containers/qemu
docker build -t localhost:5000/lego-loco-qemu:latest .
if [ $? -eq 0 ]; then
    print_success "QEMU image built successfully"
else
    print_error "QEMU build failed"
    exit 1
fi

# Step 5: Push images to local registry
print_status "Pushing images to local registry..."
docker push localhost:5000/lego-loco-frontend:latest
docker push localhost:5000/lego-loco-backend:latest
docker push localhost:5000/lego-loco-qemu:latest
print_success "All images pushed to registry"

# Step 6: Load images into kind cluster
print_status "Loading images into kind cluster..."
kind load docker-image localhost:5000/lego-loco-frontend:latest --name loco-cluster
kind load docker-image localhost:5000/lego-loco-backend:latest --name loco-cluster
kind load docker-image localhost:5000/lego-loco-qemu:latest --name loco-cluster
print_success "Images loaded into kind cluster"

# Step 7: Delete existing pods to force recreation
print_status "Deleting existing pods..."
kubectl delete pods -l app.kubernetes.io/instance=lego-loco --ignore-not-found=true
kubectl delete pods -l app=lego-loco-frontend --ignore-not-found=true
kubectl delete pods -l app=lego-loco-backend --ignore-not-found=true
kubectl delete pods -l app=lego-loco-qemu --ignore-not-found=true
print_success "Existing pods deleted"

# Step 8: Wait for pods to be fully terminated
print_status "Waiting for pods to be fully terminated..."
kubectl wait --for=delete pods -l app.kubernetes.io/instance=lego-loco --timeout=60s || true
print_success "Pod termination complete"

# Step 9: Redeploy with Helm
print_status "Redeploying with Helm..."
cd /workspaces/lego-loco-cluster/helm/loco-chart
helm upgrade --install lego-loco . \
    --set imageRepo=localhost:5000 \
    --set frontend.image=lego-loco-frontend \
    --set frontend.tag=latest \
    --set backend.image=lego-loco-backend \
    --set backend.tag=latest \
    --set emulator.image=lego-loco-qemu \
    --set emulator.tag=latest \
    --set emulator.imagePullPolicy=Always \
    --wait --timeout=300s

if [ $? -eq 0 ]; then
    print_success "Helm deployment successful"
else
    print_error "Helm deployment failed"
    exit 1
fi

# Step 10: Wait for pods to be ready
print_status "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=lego-loco --timeout=180s
print_success "All pods are ready"

# Step 11: Display pod status
print_status "Current pod status:"
kubectl get pods -l app.kubernetes.io/instance=lego-loco -o wide

# Step 12: Kill existing port forwards
print_status "Killing existing port forwards..."
pkill -f "kubectl port-forward" || true
sleep 2

# Step 13: Start port forwarding for all services
print_status "Setting up port forwarding..."

# Frontend port forward (background)
kubectl port-forward service/lego-loco-frontend 3000:80 > /dev/null 2>&1 &
FRONTEND_PID=$!
print_success "Frontend port forward started (PID: $FRONTEND_PID) - http://localhost:3000"

# Backend port forward (background)
kubectl port-forward service/lego-loco-backend 3001:3001 > /dev/null 2>&1 &
BACKEND_PID=$!
print_success "Backend port forward started (PID: $BACKEND_PID) - http://localhost:3001"

# QEMU VNC port forward (background) - assuming we have an emulator service
if kubectl get service lego-loco-emulator > /dev/null 2>&1; then
    kubectl port-forward service/lego-loco-emulator 5900:5901 > /dev/null 2>&1 &
    QEMU_PID=$!
    print_success "QEMU VNC port forward started (PID: $QEMU_PID) - vnc://localhost:5900"
else
    print_warning "QEMU emulator service not found, skipping VNC port forward"
fi

# Step 14: Test connectivity
print_status "Testing service connectivity..."

# Wait a moment for port forwards to establish
sleep 3

# Test frontend
if curl -s http://localhost:3000 > /dev/null; then
    print_success "Frontend is accessible at http://localhost:3000"
else
    print_warning "Frontend may not be ready yet at http://localhost:3000"
fi

# Test backend
if curl -s http://localhost:3001/health > /dev/null 2>&1; then
    print_success "Backend is accessible at http://localhost:3001"
else
    print_warning "Backend may not be ready yet at http://localhost:3001"
fi

# Step 15: Display summary
echo ""
print_success "🎉 Deployment completed successfully!"
echo ""
echo -e "${BLUE}📋 Service URLs:${NC}"
echo "  Frontend: http://localhost:3000"
echo "  Backend:  http://localhost:3001"
if [ ! -z "$QEMU_PID" ]; then
    echo "  QEMU VNC: vnc://localhost:5900"
fi
echo ""
echo -e "${BLUE}🔧 Port Forward PIDs:${NC}"
echo "  Frontend: $FRONTEND_PID"
echo "  Backend:  $BACKEND_PID"
if [ ! -z "$QEMU_PID" ]; then
    echo "  QEMU:     $QEMU_PID"
fi
echo ""
echo -e "${YELLOW}💡 To stop port forwards:${NC}"
echo "  pkill -f 'kubectl port-forward'"
echo ""
echo -e "${YELLOW}💡 To check logs:${NC}"
echo "  kubectl logs -l app.kubernetes.io/instance=lego-loco --follow"
echo ""
echo -e "${GREEN}🚀 Ready to test VNC functionality!${NC}"
