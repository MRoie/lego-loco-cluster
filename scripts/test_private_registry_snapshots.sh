#!/usr/bin/env bash
# test_private_registry_snapshots.sh -- Test snapshot functionality with private registry authentication

set -euo pipefail

# Configuration
NAMESPACE=${NAMESPACE:-default}
RELEASE_NAME=${RELEASE_NAME:-loco-private}
GHCR_USERNAME=${GHCR_USERNAME:-""}
GHCR_TOKEN=${GHCR_TOKEN:-""}

echo "🔐 Testing Private Registry Snapshot Functionality"
echo "=================================================="
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo ""

# Function to check if credentials are provided
check_credentials() {
    if [[ -z "$GHCR_USERNAME" || -z "$GHCR_TOKEN" ]]; then
        echo "❌ GitHub Container Registry credentials not provided!"
        echo ""
        echo "💡 To test with private registry, set these environment variables:"
        echo "   export GHCR_USERNAME=your-github-username"
        echo "   export GHCR_TOKEN=your-github-personal-access-token"
        echo ""
        echo "🔑 GitHub Token Requirements:"
        echo "   - Go to GitHub Settings > Developer settings > Personal access tokens"
        echo "   - Generate token with 'packages:read' scope (and 'packages:write' if pushing)"
        echo ""
        echo "🏃 Running in local-only mode instead..."
        test_local_mode
        exit 0
    fi
}

# Function to test with local images only
test_local_mode() {
    echo "🏠 Testing with local images (no private registry authentication)"
    echo "================================================================"
    
    # Use the existing local test configuration
    if [[ -f "test-complete-snapshots.yaml" ]]; then
        echo "📁 Using existing local configuration..."
        
        # Clean up any existing deployment
        helm uninstall "$RELEASE_NAME" --ignore-not-found
        kubectl delete pv win98-disk-pv --ignore-not-found
        sleep 3
        
        # Deploy with local images
        helm install "$RELEASE_NAME" helm/loco-chart/ -f test-complete-snapshots.yaml
        
        echo "✅ Local deployment completed"
        echo "🔍 Check pods: kubectl get pods -l app=${RELEASE_NAME}-loco-emulator"
    else
        echo "❌ Local configuration file not found"
        return 1
    fi
}

# Function to setup authentication
setup_authentication() {
    echo "🔧 Setting up private registry authentication..."
    
    # Export credentials for the setup script
    export GHCR_USERNAME="$GHCR_USERNAME"
    export GHCR_TOKEN="$GHCR_TOKEN"
    export NAMESPACE="$NAMESPACE"
    
    # Run the registry secrets setup script
    if [[ -f "scripts/setup_registry_secrets.sh" ]]; then
        ./scripts/setup_registry_secrets.sh
    else
        echo "❌ Registry secrets setup script not found"
        return 1
    fi
}

# Function to test private registry deployment
test_private_registry() {
    echo "🚀 Testing private registry deployment..."
    
    # Clean up any existing deployment
    helm uninstall "$RELEASE_NAME" --ignore-not-found
    kubectl delete pv win98-disk-pv --ignore-not-found
    sleep 3
    
    # Deploy with private registry configuration
    helm install "$RELEASE_NAME" helm/loco-chart/ -f helm/loco-chart/values-private-registry.yaml
    
    echo "✅ Private registry deployment initiated"
    echo ""
    echo "🔍 Monitoring deployment..."
    
    # Wait for deployment with timeout
    local timeout=300
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if kubectl get pods -l "app=${RELEASE_NAME}-loco-emulator" | grep -q "Running\|ContainerCreating"; then
            echo "   Pod status:"
            kubectl get pods -l "app=${RELEASE_NAME}-loco-emulator"
            
            # Check if pod is actually running
            if kubectl get pods -l "app=${RELEASE_NAME}-loco-emulator" | grep -q "Running"; then
                echo "✅ Pod is running!"
                break
            fi
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        echo "   Waiting... (${elapsed}/${timeout}s)"
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        echo "⚠️  Deployment did not complete within timeout"
        echo "📊 Final status:"
        kubectl get pods -l "app=${RELEASE_NAME}-loco-emulator"
        kubectl describe pods -l "app=${RELEASE_NAME}-loco-emulator" | tail -20
    fi
}

# Function to test snapshot download functionality
test_snapshot_download() {
    echo "📥 Testing snapshot download functionality..."
    
    # Create a test pod that demonstrates snapshot download
    cat > test-private-snapshot-download.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-private-snapshot-download
  namespace: $NAMESPACE
spec:
  imagePullSecrets:
  - name: ghcr-secret
  containers:
  - name: snapshot-test
    image: ghcr.io/mroie/qemu-loco:latest
    env:
    - name: USE_PREBUILT_SNAPSHOT
      value: "true"
    - name: SNAPSHOT_REGISTRY
      value: "ghcr.io/mroie/qemu-snapshots"
    - name: SNAPSHOT_TAG
      value: "win98-base"
    command: ["/bin/bash"]
    args: 
    - -c
    - |
      echo "🔐 Testing Private Registry Snapshot Download"
      echo "============================================="
      echo "Environment:"
      echo "  SNAPSHOT_REGISTRY: \$SNAPSHOT_REGISTRY"
      echo "  SNAPSHOT_TAG: \$SNAPSHOT_TAG"
      echo ""
      
      if command -v skopeo >/dev/null; then
        echo "✅ skopeo available for snapshot management"
        
        echo "🔍 Testing private registry access..."
        if skopeo inspect docker://\${SNAPSHOT_REGISTRY}:\${SNAPSHOT_TAG}; then
          echo "✅ Successfully accessed private snapshot registry"
          
          echo "📦 Testing snapshot container functionality..."
          if docker run --rm \${SNAPSHOT_REGISTRY}:\${SNAPSHOT_TAG}; then
            echo "✅ Snapshot container executed successfully"
          else
            echo "⚠️ Snapshot container execution failed"
          fi
        else
          echo "❌ Failed to access private snapshot registry"
          echo "   This might be expected if running without proper authentication"
        fi
      else
        echo "❌ skopeo not available"
      fi
      
      echo ""
      echo "🎯 Private registry snapshot test completed"
      sleep 60  # Keep container running for inspection
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    emptyDir: {}
  restartPolicy: Never
EOF
    
    # Apply the test pod
    kubectl apply -f test-private-snapshot-download.yaml
    
    echo "⏳ Waiting for test pod to start..."
    kubectl wait --for=condition=ready pod/test-private-snapshot-download --timeout=120s -n "$NAMESPACE" || {
        echo "⚠️ Test pod did not start successfully"
        echo "📊 Pod status:"
        kubectl get pod test-private-snapshot-download -n "$NAMESPACE"
        kubectl describe pod test-private-snapshot-download -n "$NAMESPACE" | tail -20
        return 1
    }
    
    echo "📋 Test pod logs:"
    kubectl logs test-private-snapshot-download -n "$NAMESPACE"
    
    # Cleanup
    kubectl delete pod test-private-snapshot-download -n "$NAMESPACE" --ignore-not-found
    rm -f test-private-snapshot-download.yaml
}

# Function to display summary
show_summary() {
    echo ""
    echo "📊 Private Registry Testing Summary"
    echo "=================================="
    echo ""
    
    # Check deployment status
    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        echo "✅ Helm deployment: Active"
        
        # Check pod status
        if kubectl get pods -l "app=${RELEASE_NAME}-loco-emulator" -n "$NAMESPACE" | grep -q "Running"; then
            echo "✅ Emulator pod: Running"
        else
            echo "⚠️ Emulator pod: Not running"
            kubectl get pods -l "app=${RELEASE_NAME}-loco-emulator" -n "$NAMESPACE"
        fi
    else
        echo "❌ Helm deployment: Not found"
    fi
    
    # Check secrets
    if kubectl get secret ghcr-secret -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "✅ GHCR authentication: Configured"
    else
        echo "❌ GHCR authentication: Not configured"
    fi
    
    echo ""
    echo "🔗 Useful commands:"
    echo "   Check pods: kubectl get pods -l app=${RELEASE_NAME}-loco-emulator -n $NAMESPACE"
    echo "   Check logs: kubectl logs -l app=${RELEASE_NAME}-loco-emulator -n $NAMESPACE"
    echo "   Port forward: kubectl port-forward svc/${RELEASE_NAME}-loco-emulator 6080:6080 -n $NAMESPACE"
    echo "   Clean up: helm uninstall $RELEASE_NAME -n $NAMESPACE"
    echo ""
}

# Main execution
main() {
    cd /workspaces/lego-loco-cluster || {
        echo "❌ Please run from the lego-loco-cluster directory"
        exit 1
    }
    
    check_credentials
    setup_authentication
    test_private_registry
    test_snapshot_download
    show_summary
}

# Help function
show_help() {
    cat << EOF
Test Private Registry Snapshot Functionality

This script tests the complete snapshot functionality with private registry authentication.

USAGE:
    ./test_private_registry_snapshots.sh

ENVIRONMENT VARIABLES:
    NAMESPACE         Kubernetes namespace (default: default)
    RELEASE_NAME      Helm release name (default: loco-private)
    GHCR_USERNAME     GitHub username for GHCR access
    GHCR_TOKEN        GitHub Personal Access Token

REQUIREMENTS:
    - kubectl configured and connected to cluster
    - helm installed
    - GitHub Personal Access Token with packages:read scope

EXAMPLES:
    # Test with GitHub credentials
    export GHCR_USERNAME=myuser
    export GHCR_TOKEN=ghp_xxxxxxxxxxxx
    ./test_private_registry_snapshots.sh
    
    # Test in different namespace
    export NAMESPACE=testing
    ./test_private_registry_snapshots.sh
EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
