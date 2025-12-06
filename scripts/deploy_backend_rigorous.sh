#!/bin/bash
set -e

# Configuration
SERVICE="backend"
IMAGE_NAME="lego-loco-backend"
NAMESPACE="loco"
DEPLOYMENT="loco-loco-backend"
CHART_PATH="./helm/loco-chart"

# Generate unique tag if not provided
TAG=${1:-"v$(date +%s)"}

echo "🚀 Starting rigorous deployment for $SERVICE with tag: $TAG"

# 1. Build
echo "🏗️  Building image..."
docker build -f backend/Dockerfile -t $IMAGE_NAME:$TAG .

# 2. Load
echo "📦 Loading image into Minikube..."
minikube image load $IMAGE_NAME:$TAG

# 3. Verify Image Presence
echo "🔍 Verifying image in Minikube..."
if minikube image ls | grep -q "$IMAGE_NAME:$TAG"; then
    echo "✅ Image found in cluster"
else
    echo "❌ Image NOT found in cluster!"
    exit 1
fi

# 4. Upgrade Helm Chart
echo "🔄 Upgrading Helm release..."
helm upgrade --install loco $CHART_PATH -n $NAMESPACE \
    --set $SERVICE.image=$IMAGE_NAME \
    --set $SERVICE.tag=$TAG \
    --set imageRepo="" \
    --set $SERVICE.imagePullPolicy=Never

# 5. Verify Deployment Rollout
echo "⏳ Waiting for rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s

# 6. Final Health Check
echo "💓 Checking health endpoint..."
# Wait a brief moment for service to be ready
sleep 5
SERVICE_URL=$(minikube service $DEPLOYMENT -n $NAMESPACE --url)
echo "Service URL: $SERVICE_URL"

if curl -s "$SERVICE_URL/health" | grep -q "ok"; then
    echo "✅ Backend is healthy!"
else
    echo "⚠️  Backend health check failed or not ready yet."
    echo "Check logs with: kubectl logs -n $NAMESPACE deployment/$DEPLOYMENT"
fi

echo "🎉 Deployment complete!"
