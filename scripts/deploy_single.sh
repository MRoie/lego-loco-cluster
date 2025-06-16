#!/bin/bash
# Simple deployment script for Lego Loco cluster
set -euo pipefail

# Configuration
NAMESPACE="loco"
REPLICAS=${REPLICAS:-1}
IMAGE_REPO="ghcr.io/mroie"

echo "🚀 Deploying Lego Loco cluster with $REPLICAS replicas..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "❌ helm not found. Please install helm first."
    exit 1
fi

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Build backend and frontend images if they don't exist
echo "🔨 Building backend image..."
docker build -t ${IMAGE_REPO}/loco-backend:latest ./backend/

echo "🔨 Building frontend image..."
docker build -t ${IMAGE_REPO}/loco-frontend:latest ./frontend/

# Deploy with Helm
echo "📦 Deploying with Helm..."
helm upgrade --install loco ./helm/loco-chart \
  --namespace $NAMESPACE \
  --set replicas=$REPLICAS \
  --set imageRepo=$IMAGE_REPO \
  --set emulator.imagePullPolicy=Always \
  --wait --timeout=10m

echo "✅ Deployment complete!"
echo ""
echo "📊 Cluster status:"
kubectl get pods -n $NAMESPACE
echo ""
echo "🌐 Access the frontend:"
echo "  kubectl port-forward -n $NAMESPACE svc/loco-frontend 3000:3000"
echo "  Then open: http://localhost:3000"
echo ""
echo "🖥️  Access individual VNC (example for instance-0):"
echo "  kubectl port-forward -n $NAMESPACE svc/loco-emulator 6080:6080"
echo "  Then open: http://localhost:6080"
