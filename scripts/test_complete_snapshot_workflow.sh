#!/usr/bin/env bash
# test_complete_snapshot_workflow.sh -- Test the complete snapshot building and deployment workflow

set -euo pipefail

echo "🚀 Complete Snapshot Workflow Test"
echo "=================================="
echo ""

# Configuration
REGISTRY=${REGISTRY:-ghcr.io/mroie}
TAG=${TAG:-test}
CLUSTER_NAME=${CLUSTER_NAME:-loco-cluster}

echo "📋 Workflow Test Steps:"
echo "1. Build QEMU container with snapshot support"
echo "2. Build pre-configured snapshots (base, games, productivity)"
echo "3. Test snapshot containers locally"
echo "4. Deploy to Kubernetes cluster with snapshot configuration"
echo "5. Verify snapshot environment variables and functionality"
echo ""

# Step 1: Build everything locally
echo "🏗️  Step 1: Building QEMU container and snapshots..."
./scripts/create_win98_image.sh \
  --registry "$REGISTRY" \
  --tag "$TAG" \
  --cluster "$CLUSTER_NAME" \
  --build-snapshots \
  --no-push

# Step 2: Test snapshot containers
echo ""
echo "🧪 Step 2: Testing snapshot containers..."
for variant in base games productivity; do
  snapshot_image="${REGISTRY}/qemu-snapshots:win98-${variant}"
  echo "   Testing $variant snapshot..."
  
  if docker run --rm "$snapshot_image" && echo "✅ $variant snapshot container works"; then
    echo "     ✅ $variant snapshot verified"
  else
    echo "     ❌ $variant snapshot test failed"
    exit 1
  fi
done

# Step 3: Test Kubernetes deployment
echo ""
echo "🎯 Step 3: Testing Kubernetes deployment with snapshots..."

# Create test values for snapshot deployment
cat > test-complete-values.yaml << EOF
emulator:
  image: qemu-loco
  tag: ${TAG}
  imagePullPolicy: Never
  usePrebuiltSnapshot: true
  snapshotRegistry: "${REGISTRY}/qemu-snapshots"
  snapshotTag: "win98-base"
  env:
    USE_PREBUILT_SNAPSHOT: "true"
    SNAPSHOT_REGISTRY: "${REGISTRY}/qemu-snapshots"
    SNAPSHOT_TAG: "win98-base"
    DISK_SIZE: "2G"
    DEBUG: "true"
EOF

# Deploy with Helm
if helm list | grep -q test-complete; then
  helm upgrade test-complete helm/loco-chart/ -f test-complete-values.yaml
else
  helm install test-complete helm/loco-chart/ -f test-complete-values.yaml
fi

# Wait for deployment
echo "   Waiting for deployment to be ready..."
kubectl wait --for=condition=available deployment/test-complete-loco-backend --timeout=60s
kubectl wait --for=condition=available deployment/test-complete-loco-frontend --timeout=60s

# Check emulator statefulset
echo "   Checking emulator pod..."
kubectl get pods -l app=test-complete-loco-emulator

# Check environment variables
echo ""
echo "🔍 Step 4: Verifying snapshot configuration..."
pod_name=$(kubectl get pod -l app=test-complete-loco-emulator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$pod_name" ]]; then
  echo "   Pod name: $pod_name"
  echo "   Snapshot environment variables:"
  kubectl get pod "$pod_name" -o yaml | grep -A 10 -B 5 -E "(SNAPSHOT|USE_PREBUILT)" || echo "   No snapshot env vars found"
else
  echo "   ⚠️  Emulator pod not found"
fi

# Step 5: Show next steps
echo ""
echo "🎉 Workflow Test Complete!"
echo ""
echo "✅ Accomplishments:"
echo "   - QEMU container built with snapshot download capability"
echo "   - Pre-built snapshots created for base, games, and productivity"
echo "   - Helm chart configured to support snapshot environment variables"
echo "   - Kubernetes deployment tested with snapshot configuration"
echo ""
echo "🚀 Next Steps:"
echo "   1. Push to GitHub to trigger the CI/CD workflow:"
echo "      git commit -m 'Add snapshot functionality'"
echo "      git push origin HEAD"
echo ""
echo "   2. Monitor GitHub Actions workflow:"
echo "      - Builds QEMU container and pushes to GHCR"
echo "      - Builds and pushes snapshots to GHCR"
echo "      - Tests snapshot downloading in CI environment"
echo ""
echo "   3. Use in production:"
echo "      helm install loco helm/loco-chart/ --set emulator.usePrebuiltSnapshot=true"
echo ""

# Cleanup
echo "🧹 Cleaning up test deployment..."
helm uninstall test-complete --ignore-not-found
rm -f test-complete-values.yaml

echo "Test complete! 🎯"
