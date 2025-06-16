#!/usr/bin/env bash
# Simple deployment script for single Win98 instance
set -euo pipefail

echo "🚀 Starting simple LEGO Loco cluster deployment..."

# Check if kind is available
if ! command -v kind &> /dev/null; then
    echo "❌ kind not found. Please install kind for local Kubernetes clusters."
    echo "   Install with: go install sigs.k8s.io/kind@latest"
    echo "   Or: curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl."
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "❌ helm not found. Please install helm."
    exit 1
fi

CLUSTER_NAME="lego-loco"
NAMESPACE="loco"

echo "🔧 Creating kind cluster: $CLUSTER_NAME"
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "   Cluster $CLUSTER_NAME already exists, using it..."
else
    kind create cluster --name "$CLUSTER_NAME" --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 3000
    protocol: TCP
  - containerPort: 30081
    hostPort: 3001
    protocol: TCP
  - containerPort: 30082
    hostPort: 6080
    protocol: TCP
EOF
fi

# Set kubectl context
kubectl config use-context "kind-${CLUSTER_NAME}"

echo "📦 Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "🐳 Building and loading Docker images..."

# Build backend image
echo "   Building backend..."
docker build -t loco-backend:latest ./backend/

# Build frontend image  
echo "   Building frontend..."
docker build -t loco-frontend:latest ./frontend/

# Load images into kind cluster
kind load docker-image loco-backend:latest --name "$CLUSTER_NAME"
kind load docker-image loco-frontend:latest --name "$CLUSTER_NAME"

echo "🏗️  Creating PersistentVolume for disk storage..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: win98-disk-pv
  namespace: $NAMESPACE
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /tmp/win98-disk
    type: DirectoryOrCreate
EOF

echo "⚙️  Deploying with Helm..."
helm install loco ./helm/loco-chart \
    --namespace "$NAMESPACE" \
    --set imageRepo="" \
    --set emulator.imagePullPolicy=Never \
    --set backend.imagePullPolicy=Never \
    --set frontend.imagePullPolicy=Never \
    --wait --timeout=300s

echo "🔗 Setting up port forwarding..."
# Kill any existing port forwards
pkill -f "kubectl port-forward" || true
sleep 2

# Port forward backend
kubectl port-forward svc/loco-loco-backend 3001:3001 -n "$NAMESPACE" &
# Port forward frontend  
kubectl port-forward svc/loco-loco-frontend 3000:3000 -n "$NAMESPACE" &
# Port forward emulator
kubectl port-forward svc/loco-loco-emulator 6080:6080 -n "$NAMESPACE" &

echo "✅ Deployment complete!"
echo ""
echo "🌐 Access URLs:"
echo "   Frontend: http://localhost:3000"
echo "   Backend:  http://localhost:3001"
echo "   VNC:      http://localhost:6080"
echo ""
echo "📋 Useful commands:"
echo "   kubectl get pods -n $NAMESPACE"
echo "   kubectl logs -f deployment/loco-loco-frontend -n $NAMESPACE"
echo "   kubectl logs -f deployment/loco-loco-backend -n $NAMESPACE"
echo "   kubectl logs -f statefulset/loco-loco-emulator -n $NAMESPACE"
