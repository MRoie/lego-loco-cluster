#!/bin/bash
set -e

# Configuration
NAMESPACE="loco"
CHART_PATH="./helm/loco-chart"
VALUES_FILE="./helm/loco-chart/values.yaml"

# Generate unique tag if not provided
TAG=${1:-"v$(date +%s)"}

echo "🚀 Starting rigorous full-stack deployment with tag: $TAG"
echo "📋 This will rebuild: Backend, Frontend, VR"

# Build all images
echo ""
echo "============================================"
echo "🏗️  BUILDING ALL IMAGES"
echo "============================================"

echo "📦 Building Backend..."
docker build -f backend/Dockerfile -t lego-loco-backend:$TAG .

echo "📦 Building Frontend (with --no-cache to ensure fresh nginx.conf)..."
docker build --no-cache -f frontend/Dockerfile -t lego-loco-frontend:$TAG frontend/

echo "📦 Building VR (with --no-cache for fresh config)..."
docker build --no-cache -f frontend/Dockerfile --build-arg VITE_DEFAULT_VR=true -t lego-loco-frontend:$TAG-vr frontend/

echo "📦 Building Emulator (qemu-softgpu)..."
docker build -f containers/qemu-softgpu/Dockerfile -t qemu-loco:$TAG containers/qemu-softgpu/

# Load all images into Minikube
echo ""
echo "============================================"
echo "📥 LOADING IMAGES INTO MINIKUBE"
echo "============================================"

echo "⬆️  Loading Backend..."
minikube image load lego-loco-backend:$TAG

echo "⬆️  Loading Frontend..."
minikube image load lego-loco-frontend:$TAG

echo "⬆️  Loading VR..."
minikube image load lego-loco-frontend:$TAG-vr

echo "⬆️  Loading Emulator..."
minikube image load qemu-loco:$TAG

# Verify all images
echo ""
echo "============================================"
echo "🔍 VERIFYING IMAGES IN CLUSTER"
echo "============================================"

IMAGES_OK=true

if minikube image ls | grep -q "lego-loco-backend:$TAG"; then
    echo "✅ Backend image found"
else
    echo "❌ Backend image NOT found!"
    IMAGES_OK=false
fi

if minikube image ls | grep -q "lego-loco-frontend:$TAG"; then
    echo "✅ Frontend image found"
else
    echo "❌ Frontend image NOT found!"
    IMAGES_OK=false
fi

if minikube image ls | grep -q "lego-loco-frontend:$TAG-vr"; then
    echo "✅ VR image found"
else
    echo "❌ VR image NOT found!"
    IMAGES_OK=false
fi

if minikube image ls | grep -q "qemu-loco:$TAG"; then
    echo "✅ Emulator image found"
else
    echo "❌ Emulator image NOT found!"
    IMAGES_OK=false
fi

if [ "$IMAGES_OK" = false ]; then
    echo "❌ Some images failed to load. Aborting deployment."
    exit 1
fi

# Upgrade Helm chart with all new tags
echo ""
echo "============================================"
echo "🔄 DEPLOYING WITH HELM"
echo "============================================"

helm upgrade --install loco $CHART_PATH \
    -f $VALUES_FILE \
    -n $NAMESPACE \
    --create-namespace \
    --set imageRepo="" \
    --set backend.image=lego-loco-backend \
    --set backend.tag=$TAG \
    --set backend.imagePullPolicy=Never \
    --set frontend.image=lego-loco-frontend \
    --set frontend.tag=$TAG \
    --set frontend.imagePullPolicy=Never \
    --set vr.image=lego-loco-frontend \
    --set vr.tag=$TAG-vr \
    --set vr.imagePullPolicy=Never \
    --set emulator.image=qemu-loco \
    --set emulator.tag=$TAG \
    --set emulator.imagePullPolicy=Never

# Wait for all deployments
echo ""
echo "============================================"
echo "⏳ WAITING FOR ROLLOUTS"
echo "============================================"

echo "⏳ Backend..."
kubectl rollout status deployment/loco-loco-backend -n $NAMESPACE --timeout=120s

echo "⏳ Frontend..."
kubectl rollout status deployment/loco-loco-frontend -n $NAMESPACE --timeout=120s

echo "⏳ VR..."
kubectl rollout status deployment/loco-loco-vr -n $NAMESPACE --timeout=120s

echo "⏳ Emulator..."
kubectl rollout status statefulset/loco-loco-emulator -n $NAMESPACE --timeout=120s

# Final checks
echo ""
echo "============================================"
echo "✅ DEPLOYMENT SUMMARY"
echo "============================================"

echo "📊 Pod Status:"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/part-of=lego-loco-cluster

echo ""
echo "🏷️  Deployed Tags:"
echo "  Backend:  lego-loco-backend:$TAG"
echo "  Frontend: lego-loco-frontend:$TAG"
echo "  VR:       lego-loco-frontend:$TAG-vr"
echo "  Emulator: qemu-loco:$TAG"

echo ""
echo "🎉 Full-stack deployment complete!"
echo ""
echo "💡 Next steps:"
echo "   - Test frontend: kubectl port-forward -n loco svc/loco-loco-frontend 8080:3000"
echo "   - View logs: kubectl logs -n loco -l app.kubernetes.io/component=frontend --tail=50"
