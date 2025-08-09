#!/usr/bin/env bash
# scripts/manage_ci_cluster.sh - Enhanced cluster management for CI with resource optimization
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ci-cluster-management.log"
exec > >(tee -a "$LOG_FILE") 2>&1

ACTION=${1:-"create"}
CLUSTER_NAME=${CLUSTER_NAME:-"ci-cluster"}
WORKERS=${WORKERS:-1}
KUBERNETES_VERSION=${KUBERNETES_VERSION:-v1.28.3}

echo "=== CI Cluster Management - Action: $ACTION ===" && date

# Optimized resource allocation for CI environments
if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    # CI environment - use minimum required resources that actually work
    MINIKUBE_CPUS=${MINIKUBE_CPUS:-2}     # Minimum required by minikube
    MINIKUBE_MEMORY=${MINIKUBE_MEMORY:-2000}  # Increased to exceed minikube minimum of 1800MB
    MINIKUBE_DISK=${MINIKUBE_DISK:-10g}    # Increased for stability
    echo "CI environment detected - using minimal but working resources (CPUs: $MINIKUBE_CPUS, Memory: ${MINIKUBE_MEMORY}MB, Disk: $MINIKUBE_DISK)"
else
    # Development environment
    MINIKUBE_CPUS=${MINIKUBE_CPUS:-2}
    MINIKUBE_MEMORY=${MINIKUBE_MEMORY:-4096}
    MINIKUBE_DISK=${MINIKUBE_DISK:-20g}
    echo "Development environment - using standard resources"
fi

install_minikube() {
    if ! command -v minikube &> /dev/null; then
        echo "Installing minikube" && date
        curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        chmod +x minikube
        # Always install to current directory and add to PATH for CI compatibility
        export PATH="$PWD:$PATH"
        echo "Minikube installed and added to PATH"
    else
        echo "Minikube already available: $(minikube version --short)"
    fi
}

validate_resources() {
    echo "Validating system resources" && date
    available_cpus=$(nproc)
    available_memory_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    available_memory_mb=$((available_memory_kb / 1024))
    
    echo "System resources: CPUs=$available_cpus, Memory=${available_memory_mb}MB"
    echo "Requested resources: CPUs=$MINIKUBE_CPUS, Memory=${MINIKUBE_MEMORY}MB"
    
    # In CI, we often have resource limits so we'll be lenient
    if [ "$available_cpus" -lt "$MINIKUBE_CPUS" ]; then
        echo "⚠️  Warning: Available CPUs ($available_cpus) less than requested ($MINIKUBE_CPUS)"
        if [[ -n "${CI:-}" ]]; then
            echo "CI environment - continuing with warning"
        fi
    fi
    
    if [ "$available_memory_mb" -lt "$MINIKUBE_MEMORY" ]; then
        echo "⚠️  Warning: Available memory (${available_memory_mb}MB) less than requested (${MINIKUBE_MEMORY}MB)"
        if [[ -n "${CI:-}" ]]; then
            echo "CI environment - continuing with warning"
        fi
    fi
}

create_cluster() {
    echo "Creating cluster: $CLUSTER_NAME" && date
    
    # Clean up any existing cluster
    minikube delete -p "$CLUSTER_NAME" || true
    
    # Validate prerequisites
    install_minikube
    validate_resources
    
    # Configure minikube arguments
    MINIKUBE_ARGS="-p $CLUSTER_NAME \
        --driver=docker \
        --kubernetes-version=$KUBERNETES_VERSION \
        --nodes=$WORKERS \
        --cpus=$MINIKUBE_CPUS \
        --memory=$MINIKUBE_MEMORY \
        --disk-size=$MINIKUBE_DISK \
        --container-runtime=docker \
        --wait=true \
        --wait-timeout=300s"
    
    # Add --force flag in CI environments to bypass root privilege warnings
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        MINIKUBE_ARGS="$MINIKUBE_ARGS --force"
        echo "CI environment detected - adding --force flag"
    fi
    
    # Retry logic for cluster creation
    MAX_RETRIES=3
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if minikube start $MINIKUBE_ARGS; then
            echo "✅ Cluster $CLUSTER_NAME started successfully" && date
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "❌ Attempt $RETRY_COUNT failed to start cluster" && date
            
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo "Retrying in 30 seconds..." && date
                sleep 30
                minikube delete -p "$CLUSTER_NAME" || true
                docker system prune -f || true
            else
                echo "❌ Failed to start cluster after $MAX_RETRIES attempts" && date
                collect_diagnostics
                exit 1
            fi
        fi
    done
    
    # Setup cluster
    setup_cluster
}

setup_cluster() {
    echo "Setting up cluster addons and configuration" && date
    
    # Enable minimal required addons only for CI
    minikube addons enable storage-provisioner -p "$CLUSTER_NAME" || echo "⚠️  Failed to enable storage-provisioner"
    
    # Skip heavy addons in CI to save resources
    if [[ -z "${CI:-}" ]]; then
        minikube addons enable ingress -p "$CLUSTER_NAME" || echo "⚠️  Failed to enable ingress"
        minikube addons enable metrics-server -p "$CLUSTER_NAME" || echo "⚠️  Failed to enable metrics-server"
    fi
    
    # Set up kubectl context
    kubectl config use-context "$CLUSTER_NAME"
    
    # Export kubeconfig for GitHub Actions
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        echo "KUBECONFIG=$HOME/.kube/config" >> "$GITHUB_ENV"
    fi
    
    # Wait for basic cluster readiness
    echo "Waiting for cluster to be ready" && date
    kubectl wait --for=condition=Ready node --all --timeout=300s
    kubectl wait --for=condition=Ready -n kube-system pod -l k8s-app=kube-dns --timeout=120s || echo "⚠️  DNS pods not ready"
    
    echo "Cluster status:" && date
    kubectl get nodes -o wide
    kubectl get pods -A
}

destroy_cluster() {
    echo "Destroying cluster: $CLUSTER_NAME" && date
    minikube delete -p "$CLUSTER_NAME" || true
    docker system prune -f || true
    echo "✅ Cluster $CLUSTER_NAME destroyed" && date
}

collect_diagnostics() {
    echo "Collecting diagnostic information" && date
    minikube logs -p "$CLUSTER_NAME" || true
    docker ps -a || true
    docker images || true
    free -h || true
    df -h || true
}

status_cluster() {
    echo "Cluster status: $CLUSTER_NAME" && date
    if minikube status -p "$CLUSTER_NAME" 2>/dev/null; then
        kubectl get nodes -o wide
        kubectl get pods -A
    else
        echo "Cluster $CLUSTER_NAME is not running"
    fi
}

case "$ACTION" in
    "create")
        create_cluster
        ;;
    "destroy")
        destroy_cluster
        ;;
    "status")
        status_cluster
        ;;
    "setup")
        setup_cluster
        ;;
    *)
        echo "Usage: $0 {create|destroy|status|setup}"
        echo "Environment variables:"
        echo "  CLUSTER_NAME=${CLUSTER_NAME}"
        echo "  WORKERS=${WORKERS}"
        echo "  MINIKUBE_CPUS=${MINIKUBE_CPUS}"
        echo "  MINIKUBE_MEMORY=${MINIKUBE_MEMORY}"
        exit 1
        ;;
esac

echo "=== CI Cluster Management Complete - Action: $ACTION ===" && date