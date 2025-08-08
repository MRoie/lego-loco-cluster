#!/usr/bin/env bash
# scripts/create_minikube_cluster.sh -- create a Minikube cluster for CI and wait for readiness
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/create-minikube-cluster.log"
exec > >(tee -a "$LOG_FILE") 2>&1

WORKERS=${WORKERS:-1}
KUBERNETES_VERSION=${KUBERNETES_VERSION:-v1.28.3}

# Environment-specific resource allocation
if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    # CI environment - use minimum required resources
    MINIKUBE_CPUS=${MINIKUBE_CPUS:-2}  # Minimum required by minikube
    MINIKUBE_MEMORY=${MINIKUBE_MEMORY:-2048}
    echo "CI environment detected - using minimal resources (CPUs: $MINIKUBE_CPUS, Memory: ${MINIKUBE_MEMORY}MB)"
else
    # Development environment - can use more resources
    MINIKUBE_CPUS=${MINIKUBE_CPUS:-2}
    MINIKUBE_MEMORY=${MINIKUBE_MEMORY:-4096}
    echo "Development environment - using standard resources (CPUs: $MINIKUBE_CPUS, Memory: ${MINIKUBE_MEMORY}MB)"
fi

echo "Creating Minikube cluster with $WORKERS nodes" && date

# Install minikube if not present
if ! command -v minikube &> /dev/null; then
    echo "Installing minikube" && date
    curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube
    # Always install to current directory and add to PATH for CI compatibility
    export PATH="$PWD:$PATH"
    echo "Minikube installed to current directory and added to PATH"
    echo "PATH is now: $PATH"
fi

# Ensure docker daemon is running
if ! pgrep dockerd >/dev/null 2>&1; then
    echo "Starting Docker daemon" && date
    dockerd >"$LOG_DIR/dockerd.log" 2>&1 &
    echo "Waiting for Docker daemon to be ready" && date
    timeout=30
    while ! docker info >/dev/null 2>&1; do
        ((timeout--))
        if [ $timeout -le 0 ]; then
            echo "Docker daemon failed to start within the timeout period" && date
            exit 1
        fi
        sleep 1
    done
fi

# Delete existing cluster if it exists
minikube delete || true

# Validate system resources before attempting cluster creation
echo "Validating system resources" && date
available_cpus=$(nproc)
available_memory_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
available_memory_mb=$((available_memory_kb / 1024))

echo "System resources: CPUs=$available_cpus, Memory=${available_memory_mb}MB"
echo "Requested resources: CPUs=$MINIKUBE_CPUS, Memory=${MINIKUBE_MEMORY}MB"

if [ "$available_cpus" -lt "$MINIKUBE_CPUS" ]; then
    echo "⚠️  Warning: Available CPUs ($available_cpus) less than requested ($MINIKUBE_CPUS)"
    echo "Attempting to start anyway as CI environments may have CPU limits"
fi

if [ "$available_memory_mb" -lt "$MINIKUBE_MEMORY" ]; then
    echo "⚠️  Warning: Available memory (${available_memory_mb}MB) less than requested (${MINIKUBE_MEMORY}MB)"
    echo "Attempting to start anyway as CI environments may have memory limits"
fi

# Start minikube cluster with minimal configuration for CI compatibility
echo "Starting Minikube cluster" && date

# Retry logic for minikube start with exponential backoff
MAX_RETRIES=3
RETRY_COUNT=0
RETRY_DELAY=30

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if minikube start \
        --driver=docker \
        --kubernetes-version="$KUBERNETES_VERSION" \
        --nodes="$WORKERS" \
        --cpus="$MINIKUBE_CPUS" \
        --memory="$MINIKUBE_MEMORY" \
        --disk-size=8g \
        --container-runtime=docker \
        --wait=true \
        --wait-timeout=600s; then
        echo "✅ Minikube cluster started successfully" && date
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "❌ Attempt $RETRY_COUNT failed to start Minikube cluster" && date
        
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "Retrying in ${RETRY_DELAY} seconds..." && date
            sleep $RETRY_DELAY
            RETRY_DELAY=$((RETRY_DELAY * 2))  # Exponential backoff
            
            # Clean up before retry
            minikube delete || true
            docker system prune -f || true
        else
            echo "❌ Failed to start Minikube cluster after $MAX_RETRIES attempts" && date
            echo "Collecting diagnostic information..."
            minikube logs || true
            docker ps -a || true
            docker images || true
            exit 1
        fi
    fi
done

# Enable required addons with better error handling
echo "Enabling Minikube addons" && date
minikube addons enable ingress || echo "⚠️  Failed to enable ingress addon" 
minikube addons enable metrics-server || echo "⚠️  Failed to enable metrics-server addon"
minikube addons enable storage-provisioner || echo "⚠️  Failed to enable storage-provisioner addon"

# Additional wait time for addons to be ready
echo "Waiting for addons to initialize" && date
sleep 10

# Set up kubectl context
kubectl config use-context minikube
export KUBECONFIG="$HOME/.kube/config"

# Provide kubeconfig to subsequent steps in GitHub Actions
if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "KUBECONFIG=$KUBECONFIG" >> "$GITHUB_ENV"
fi

# Wait for cluster to be fully ready with increased timeouts for CI
echo "Waiting for cluster components to be ready" && date
kubectl wait --for=condition=Ready node --all --timeout=600s
echo "Nodes ready, waiting for system pods" && date
kubectl wait --for=condition=Ready -n kube-system --all pods --timeout=600s

echo "Deploying base manifests (skipped for basic cluster setup)" && date
# Skip base manifests deployment to avoid helm/kustomize issues in CI
# kubectl apply -k kustomize/base || echo "⚠️  Base manifests deployment skipped"

echo "Checking initial cluster status" && date
kubectl get pods -A -o wide

echo "Waiting for base pods to be ready with extended timeout" && date  
# Wait for specific pods instead of all pods to avoid timing issues
kubectl wait --for=condition=Ready pod -A -l k8s-app=kube-dns --timeout=300s || echo "⚠️  DNS pods not ready"
kubectl wait --for=condition=Ready pod -A -l app.kubernetes.io/name=ingress-nginx --timeout=300s || echo "⚠️  Ingress pods not ready"

kubectl get pods -A -o wide
kubectl cluster-info

echo "Minikube cluster setup complete" && date