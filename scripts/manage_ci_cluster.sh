#!/usr/bin/env bash
# scripts/manage_ci_cluster.sh - Enhanced cluster management for CI with MAXIMUM resource optimization
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

# MAXIMUM resource allocation for CI environments based on GitHub Actions runner specs
# GitHub Actions runners: 2-core CPU, 7GB RAM, 14GB SSD
if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    # CI environment - use MAXIMUM available resources for stability
    MINIKUBE_CPUS=${MINIKUBE_CPUS:-2}          # Use all available CPUs
    MINIKUBE_MEMORY=${MINIKUBE_MEMORY:-5120}   # Use ~5GB of 7GB available (leave headroom)
    MINIKUBE_DISK=${MINIKUBE_DISK:-10g}        # Use majority of available disk
    echo "CI environment detected - using MAXIMUM available resources (CPUs: $MINIKUBE_CPUS, Memory: ${MINIKUBE_MEMORY}MB, Disk: $MINIKUBE_DISK)"
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
    available_disk_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    echo "System resources: CPUs=$available_cpus, Memory=${available_memory_mb}MB, Disk=${available_disk_gb}GB"
    echo "Requested resources: CPUs=$MINIKUBE_CPUS, Memory=${MINIKUBE_MEMORY}MB"
    
    # In CI, show warnings but continue (resource limits may be higher than detected)
    if [ "$available_cpus" -lt "$MINIKUBE_CPUS" ]; then
        echo "⚠️  Warning: Available CPUs ($available_cpus) less than requested ($MINIKUBE_CPUS)"
        if [[ -n "${CI:-}" ]]; then
            echo "CI environment - continuing with warning (limits may be higher than detected)"
        fi
    fi
    
    if [ "$available_memory_mb" -lt "$MINIKUBE_MEMORY" ]; then
        echo "⚠️  Warning: Available memory (${available_memory_mb}MB) less than requested (${MINIKUBE_MEMORY}MB)"
        if [[ -n "${CI:-}" ]]; then
            echo "CI environment - continuing with warning (limits may be higher than detected)"
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
    
    # Configure minikube arguments with CI best practices
    TIMEOUT_SECONDS=900  # Increased to 15 minutes for maximum stability
    MINIKUBE_ARGS="-p $CLUSTER_NAME \
        --driver=docker \
        --kubernetes-version=$KUBERNETES_VERSION \
        --nodes=$WORKERS \
        --cpus=$MINIKUBE_CPUS \
        --memory=$MINIKUBE_MEMORY \
        --disk-size=$MINIKUBE_DISK \
        --container-runtime=docker \
        --wait=true \
        --wait-timeout=${TIMEOUT_SECONDS}s \
        --delete-on-failure=true \
        --alsologtostderr"
    
    # Add CI-specific flags for maximum compatibility
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        MINIKUBE_ARGS="$MINIKUBE_ARGS --force --no-vtx-check --extra-config=kubelet.housekeeping-interval=10s"
        echo "CI environment detected - adding maximum compatibility flags"
    fi
    
    # Retry logic with exponential backoff
    MAX_RETRIES=3
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        echo "Starting minikube cluster (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)" && date
        
        if minikube start $MINIKUBE_ARGS; then
            echo "✅ Cluster $CLUSTER_NAME started successfully" && date
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "❌ Attempt $RETRY_COUNT failed to start cluster" && date
            
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                WAIT_TIME=$((30 * RETRY_COUNT))
                echo "Retrying in ${WAIT_TIME} seconds..." && date
                sleep $WAIT_TIME
                
                # Clean up before retry
                minikube delete -p "$CLUSTER_NAME" || true
                docker system prune -f || true
                
                # Free up memory
                echo "Freeing up system resources..." && date
                sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
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
    
    # Enable only essential addons for CI efficiency
    minikube addons enable storage-provisioner -p "$CLUSTER_NAME" || echo "⚠️  Failed to enable storage-provisioner"
    
    # Skip heavy addons in CI to save resources
    if [[ -z "${CI:-}" ]]; then
        echo "Development environment - enabling additional addons"
        minikube addons enable ingress -p "$CLUSTER_NAME" || echo "⚠️  Failed to enable ingress"
        minikube addons enable metrics-server -p "$CLUSTER_NAME" || echo "⚠️  Failed to enable metrics-server"
    else
        echo "CI environment - skipping resource-heavy addons for efficiency"
    fi
    
    # Set up kubectl context
    kubectl config use-context "$CLUSTER_NAME"
    
    # Export kubeconfig for GitHub Actions
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        echo "KUBECONFIG=$HOME/.kube/config" >> "$GITHUB_ENV"
    fi
    
    # Wait for basic cluster readiness with extended timeouts
    echo "Waiting for cluster to be ready" && date
    kubectl wait --for=condition=Ready node --all --timeout=600s
    kubectl wait --for=condition=Ready -n kube-system pod -l k8s-app=kube-dns --timeout=300s || echo "⚠️  DNS pods not ready"
    
    echo "Cluster status:" && date
    kubectl get nodes -o wide
    kubectl get pods -A --field-selector=status.phase!=Running 2>/dev/null | head -10 || true
    
    # Show resource usage
    echo "Resource usage:" && date
    kubectl top nodes 2>/dev/null || echo "Metrics not available yet"
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
    minikube status -p "$CLUSTER_NAME" || true
    docker ps -a || true
    docker images || true
    free -h || true
    df -h || true
    echo "System resource usage:" && date
    ps aux --sort=-%mem | head -10 || true
}

status_cluster() {
    echo "Cluster status: $CLUSTER_NAME" && date
    if minikube status -p "$CLUSTER_NAME" 2>/dev/null; then
        kubectl get nodes -o wide
        kubectl get pods -A
        echo "Resource usage:" && date
        kubectl top nodes 2>/dev/null || echo "Metrics not available"
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