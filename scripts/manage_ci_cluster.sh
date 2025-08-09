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
    MINIKUBE_MEMORY=${MINIKUBE_MEMORY:-4096}   # Use ~4GB of 7GB available (conservative for CI)
    MINIKUBE_DISK=${MINIKUBE_DISK:-8g}         # Use majority of available disk
    TIMEOUT_SECONDS=1200  # Increased to 20 minutes for maximum stability in CI
    echo "CI environment detected - using MAXIMUM available resources (CPUs: $MINIKUBE_CPUS, Memory: ${MINIKUBE_MEMORY}MB, Disk: $MINIKUBE_DISK, Timeout: ${TIMEOUT_SECONDS}s)"
else
    # Development environment
    MINIKUBE_CPUS=${MINIKUBE_CPUS:-2}
    MINIKUBE_MEMORY=${MINIKUBE_MEMORY:-4096}
    MINIKUBE_DISK=${MINIKUBE_DISK:-20g}
    TIMEOUT_SECONDS=900
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
    
    # Pre-creation diagnostics
    echo "=== PRE-CREATION SYSTEM DIAGNOSTICS ===" && date
    collect_pre_creation_diagnostics
    
    # Clean up any existing cluster
    echo "Cleaning up any existing cluster..." && date
    minikube delete -p "$CLUSTER_NAME" || true
    
    # Validate prerequisites
    install_minikube
    validate_resources
    
    # Configure minikube arguments with CI best practices
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
        --alsologtostderr \
        --v=2"
    
    # Add CI-specific flags for maximum compatibility
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        MINIKUBE_ARGS="$MINIKUBE_ARGS --force --no-vtx-check --extra-config=kubelet.housekeeping-interval=10s"
        echo "CI environment detected - adding maximum compatibility flags"
    fi
    
    echo "Final minikube arguments: $MINIKUBE_ARGS" && date
    
    # Retry logic with enhanced diagnostics
    MAX_RETRIES=3
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        echo "=== CLUSTER CREATION ATTEMPT $((RETRY_COUNT + 1))/$MAX_RETRIES ===" && date
        
        # Start monitoring resources in background during cluster creation
        start_resource_monitoring &
        MONITOR_PID=$!
        
        # Comprehensive minikube start with detailed logging
        echo "Starting minikube with detailed logging..." && date
        set +e  # Don't exit on error so we can collect diagnostics
        
        timeout ${TIMEOUT_SECONDS} stdbuf -oL -eL minikube start $MINIKUBE_ARGS > "$LOG_DIR/minikube-start-attempt-$((RETRY_COUNT + 1)).log" 2>&1
        START_EXIT_CODE=$?
        
        # Stop resource monitoring
        kill $MONITOR_PID 2>/dev/null || true
        wait $MONITOR_PID 2>/dev/null || true
        
        set -e  # Re-enable exit on error
        
        # Check if start was successful
        if [ $START_EXIT_CODE -eq 0 ] && minikube status -p "$CLUSTER_NAME" >/dev/null 2>&1; then
            echo "✅ Cluster $CLUSTER_NAME started successfully" && date
            
            # Post-creation diagnostics
            echo "=== POST-CREATION CLUSTER DIAGNOSTICS ===" && date
            collect_post_creation_diagnostics
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "❌ Attempt $RETRY_COUNT failed to start cluster (exit code: $START_EXIT_CODE)" && date
            
            # Collect detailed failure diagnostics
            echo "=== FAILURE DIAGNOSTICS ATTEMPT $RETRY_COUNT ===" && date
            collect_failure_diagnostics $RETRY_COUNT
            
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                WAIT_TIME=$((30 * RETRY_COUNT))
                echo "Retrying in ${WAIT_TIME} seconds..." && date
                sleep $WAIT_TIME
                
                # Comprehensive cleanup before retry
                cleanup_before_retry
            else
                echo "❌ Failed to start cluster after $MAX_RETRIES attempts" && date
                collect_final_failure_diagnostics
                exit 1
            fi
        fi
    done
    
    # Setup cluster
    setup_cluster
}

setup_cluster() {
    echo "Setting up cluster addons and configuration" && date
    local setup_log="$LOG_DIR/cluster-setup.log"
    
    {
        echo "=== CLUSTER SETUP STARTING ==="
        date
        
        # Enable only essential addons for CI efficiency
        echo "Enabling storage provisioner..."
        minikube addons enable storage-provisioner -p "$CLUSTER_NAME" || echo "⚠️  Failed to enable storage-provisioner"
        
        # Skip heavy addons in CI to save resources
        if [[ -z "${CI:-}" ]]; then
            echo "Development environment - enabling additional addons"
            minikube addons enable ingress -p "$CLUSTER_NAME" || echo "⚠️  Failed to enable ingress"
            minikube addons enable metrics-server -p "$CLUSTER_NAME" || echo "⚠️  Failed to enable metrics-server"
        else
            echo "CI environment - skipping resource-heavy addons for efficiency"
        fi
        
        # List enabled addons
        echo "Enabled addons:"
        minikube addons list -p "$CLUSTER_NAME" | grep enabled || true
        
        # Set up kubectl context
        echo "Setting up kubectl context..."
        kubectl config use-context "$CLUSTER_NAME"
        kubectl config current-context
        
        # Export kubeconfig for GitHub Actions
        if [[ -n "${GITHUB_ENV:-}" ]]; then
            echo "KUBECONFIG=$HOME/.kube/config" >> "$GITHUB_ENV"
            echo "KUBECONFIG exported for GitHub Actions"
        fi
        
        # Wait for basic cluster readiness with extended timeouts
        echo "Waiting for cluster to be ready"
        date
        
        echo "Waiting for nodes..."
        kubectl wait --for=condition=Ready node --all --timeout=600s
        
        echo "Waiting for DNS pods..."
        kubectl wait --for=condition=Ready -n kube-system pod -l k8s-app=kube-dns --timeout=300s || echo "⚠️  DNS pods not ready"
        
        echo "Cluster status:" && date
        kubectl get nodes -o wide
        kubectl get pods -A --field-selector=status.phase!=Running 2>/dev/null | head -10 || true
        
        # Show detailed cluster information
        echo "=== DETAILED CLUSTER INFORMATION ==="
        echo "Cluster info:"
        kubectl cluster-info
        
        echo "All pods status:"
        kubectl get pods -A -o wide
        
        echo "System events:"
        kubectl get events -A --sort-by='.lastTimestamp' | tail -10 || true
        
        # Show resource usage
        echo "Resource usage:" && date
        kubectl top nodes 2>/dev/null || echo "Metrics not available yet"
        kubectl top pods -A 2>/dev/null | head -10 || echo "Pod metrics not available yet"
        
        echo "=== CLUSTER SETUP COMPLETED ==="
        date
        
    } | tee -a "$setup_log"
}

destroy_cluster() {
    echo "Destroying cluster: $CLUSTER_NAME" && date
    minikube delete -p "$CLUSTER_NAME" || true
    docker system prune -f || true
    echo "✅ Cluster $CLUSTER_NAME destroyed" && date
}

start_resource_monitoring() {
    echo "Starting continuous resource monitoring..." && date
    RESOURCE_LOG="$LOG_DIR/resource-monitoring-$(date +%s).log"
    
    while true; do
        echo "=== RESOURCE SNAPSHOT $(date) ===" >> "$RESOURCE_LOG"
        echo "Memory:" >> "$RESOURCE_LOG"
        free -h >> "$RESOURCE_LOG" 2>/dev/null || true
        echo "Disk:" >> "$RESOURCE_LOG"
        df -h / >> "$RESOURCE_LOG" 2>/dev/null || true
        echo "CPU Load:" >> "$RESOURCE_LOG"
        uptime >> "$RESOURCE_LOG" 2>/dev/null || true
        echo "Docker processes:" >> "$RESOURCE_LOG"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" >> "$RESOURCE_LOG" 2>/dev/null || true
        echo "Top memory consumers:" >> "$RESOURCE_LOG"
        ps aux --sort=-%mem | head -5 >> "$RESOURCE_LOG" 2>/dev/null || true
        echo "" >> "$RESOURCE_LOG"
        sleep 10
    done
}

collect_pre_creation_diagnostics() {
    local diag_file="$LOG_DIR/pre-creation-diagnostics.log"
    echo "Collecting pre-creation diagnostics to $diag_file" && date
    
    {
        echo "=== SYSTEM INFORMATION ==="
        uname -a || true
        cat /proc/version || true
        
        echo "=== SYSTEM RESOURCES ==="
        free -h || true
        df -h || true
        lscpu | head -20 || true
        
        echo "=== DOCKER INFORMATION ==="
        docker version || true
        docker info || true
        docker ps -a || true
        docker images || true
        
        echo "=== MINIKUBE STATUS ==="
        minikube profile list || true
        minikube status -p "$CLUSTER_NAME" || echo "Cluster not found (expected)"
        
        echo "=== KUBERNETES TOOLS ==="
        kubectl version --client=true || true
        helm version --short || true
        
        echo "=== NETWORK STATUS ==="
        ss -tuln | head -20 || true
        
        echo "=== SYSTEM PROCESSES ==="
        ps aux --sort=-%mem | head -10 || true
        
    } > "$diag_file" 2>&1
}

collect_post_creation_diagnostics() {
    local diag_file="$LOG_DIR/post-creation-diagnostics.log"
    echo "Collecting post-creation diagnostics to $diag_file" && date
    
    {
        echo "=== MINIKUBE CLUSTER STATUS ==="
        minikube status -p "$CLUSTER_NAME" || true
        minikube profile list || true
        
        echo "=== MINIKUBE LOGS ==="
        minikube logs -p "$CLUSTER_NAME" --length=100 || true
        
        echo "=== KUBERNETES CLUSTER STATUS ==="
        kubectl get nodes -o wide || true
        kubectl get pods -A || true
        kubectl get events -A --sort-by='.lastTimestamp' | tail -20 || true
        
        echo "=== CLUSTER RESOURCE USAGE ==="
        kubectl top nodes || echo "Metrics not available"
        kubectl top pods -A || echo "Metrics not available"
        
        echo "=== DOCKER CONTAINERS ==="
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}" || true
        
        echo "=== SYSTEM RESOURCES AFTER CREATION ==="
        free -h || true
        df -h || true
        uptime || true
        
    } > "$diag_file" 2>&1
}

collect_failure_diagnostics() {
    local attempt_num=$1
    local diag_file="$LOG_DIR/failure-diagnostics-attempt-$attempt_num.log"
    echo "Collecting failure diagnostics (attempt $attempt_num) to $diag_file" && date
    
    {
        echo "=== FAILURE ANALYSIS ATTEMPT $attempt_num ==="
        date
        
        echo "=== MINIKUBE STATUS AND LOGS ==="
        minikube status -p "$CLUSTER_NAME" || true
        minikube logs -p "$CLUSTER_NAME" || true
        
        echo "=== MINIKUBE DOCKER ENV ==="
        minikube docker-env -p "$CLUSTER_NAME" || true
        
        echo "=== DOCKER SYSTEM STATUS ==="
        docker system df || true
        docker system events --since=5m --until=now || true
        docker ps -a || true
        
        echo "=== DOCKER CONTAINER LOGS ==="
        # Get logs from any minikube-related containers
        for container in $(docker ps -a --filter="name=*minikube*" --format="{{.Names}}" | head -5); do
            echo "--- Container $container logs ---"
            docker logs --tail=50 "$container" 2>&1 || true
        done
        
        echo "=== SYSTEM RESOURCE STATUS ==="
        free -h || true
        df -h || true
        ps aux --sort=-%mem | head -10 || true
        
        echo "=== NETWORK STATUS ==="
        ss -tuln | grep -E ':(6443|8443|2376|22)' || true
        
        echo "=== KERNEL MESSAGES ==="
        dmesg | tail -20 || true
        
        echo "=== SYSTEMD JOURNAL ==="
        journalctl --no-pager -u docker --since="5 minutes ago" || true
        
    } > "$diag_file" 2>&1
}

collect_final_failure_diagnostics() {
    local diag_file="$LOG_DIR/final-failure-diagnostics.log"
    echo "Collecting final failure diagnostics to $diag_file" && date
    
    {
        echo "=== FINAL FAILURE ANALYSIS ==="
        date
        
        echo "=== ALL MINIKUBE PROFILES ==="
        minikube profile list || true
        
        echo "=== COMPLETE MINIKUBE LOGS ==="
        minikube logs -p "$CLUSTER_NAME" || true
        
        echo "=== DOCKER SYSTEM INFORMATION ==="
        docker info || true
        docker system df || true
        docker version || true
        
        echo "=== ALL DOCKER CONTAINERS ==="
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}\t{{.CreatedAt}}" || true
        
        echo "=== DOCKER SYSTEM EVENTS ==="
        docker system events --since=10m --until=now || true
        
        echo "=== COMPLETE SYSTEM STATUS ==="
        uptime || true
        free -h || true
        df -h || true
        lsblk || true
        mount | grep docker || true
        
        echo "=== COMPLETE PROCESS LIST ==="
        ps aux --sort=-%mem | head -20 || true
        
        echo "=== NETWORK CONFIGURATION ==="
        ip addr show || true
        ip route show || true
        ss -tuln || true
        
        echo "=== KERNEL AND SYSTEM LOGS ==="
        dmesg | tail -50 || true
        journalctl --no-pager --since="10 minutes ago" | tail -50 || true
        
    } > "$diag_file" 2>&1
}

cleanup_before_retry() {
    echo "Performing comprehensive cleanup before retry..." && date
    
    # Stop and remove all minikube-related containers
    docker ps -a --filter="name=*minikube*" --format="{{.Names}}" | xargs -r docker rm -f || true
    
    # Clean up minikube profile
    minikube delete -p "$CLUSTER_NAME" || true
    
    # Clean up Docker system
    docker system prune -f || true
    docker volume prune -f || true
    
    # Free up system resources
    echo "Freeing up system resources..." && date
    sync || true
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    
    # Wait for cleanup to complete
    sleep 5
    
    echo "Cleanup completed" && date
}

collect_diagnostics() {
    echo "Collecting basic diagnostic information" && date
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