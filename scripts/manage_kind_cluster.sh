#!/usr/bin/env bash
# scripts/manage_kind_cluster.sh - KIND-based cluster management optimized for CI environments
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/kind-cluster-management.log"
exec > >(tee -a "$LOG_FILE") 2>&1

ACTION=${1:-"create"}
CLUSTER_NAME=${CLUSTER_NAME:-"ci-cluster"}
KUBERNETES_VERSION=${KUBERNETES_VERSION:-v1.28.3}

echo "=== KIND Cluster Management - Action: $ACTION ===" && date

# KIND configuration optimized for CI environments
KIND_CONFIG_FILE="/tmp/kind-config.yaml"

create_kind_config() {
    cat > "$KIND_CONFIG_FILE" << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: $CLUSTER_NAME
nodes:
- role: control-plane
  image: kindest/node:$KUBERNETES_VERSION
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
        authorization-mode: "AlwaysAllow"
  - |
    kind: KubeletConfiguration
    imageGCHighThresholdPercent: 99
    imageGCLowThresholdPercent: 90
    housekeepingInterval: "10s"
  - |
    kind: ClusterConfiguration
    controllerManager:
      extraArgs:
        enable-hostpath-provisioner: "true"
  portMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
  - containerPort: 30001
    hostPort: 30001
    protocol: TCP
  - containerPort: 30002
    hostPort: 30002
    protocol: TCP
EOF
    echo "KIND configuration created: $KIND_CONFIG_FILE"
}

install_kind() {
    if ! command -v kind &> /dev/null; then
        echo "Installing KIND" && date
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind || mv ./kind ~/kind
        if [[ ! -f /usr/local/bin/kind ]]; then
            export PATH="$HOME:$PATH"
        fi
        echo "KIND installed"
    else
        echo "KIND already available: $(kind version)"
    fi
}

create_cluster() {
    echo "Creating KIND cluster: $CLUSTER_NAME" && date
    
    # Pre-creation diagnostics
    echo "=== PRE-CREATION SYSTEM DIAGNOSTICS ===" && date
    collect_pre_creation_diagnostics
    
    # Clean up any existing cluster
    echo "Cleaning up any existing cluster..." && date
    kind delete cluster --name "$CLUSTER_NAME" || true
    
    # Install KIND
    install_kind
    
    # Create KIND configuration
    create_kind_config
    
    echo "Creating KIND cluster with configuration..." && date
    set +e  # Don't exit on error so we can collect diagnostics
    
    # Start resource monitoring
    start_resource_monitoring &
    MONITOR_PID=$!
    
    # Create cluster with timeout
    kind create cluster --config="$KIND_CONFIG_FILE" --wait=300s --verbosity=1 > "$LOG_DIR/kind-create.log" 2>&1
    CREATE_EXIT_CODE=$?
    
    # Stop resource monitoring
    kill $MONITOR_PID 2>/dev/null || true
    wait $MONITOR_PID 2>/dev/null || true
    
    set -e  # Re-enable exit on error
    
    if [ $CREATE_EXIT_CODE -eq 0 ]; then
        echo "✅ KIND cluster $CLUSTER_NAME created successfully" && date
        
        # Post-creation diagnostics
        echo "=== POST-CREATION CLUSTER DIAGNOSTICS ===" && date
        collect_post_creation_diagnostics
        
        # Setup cluster
        setup_cluster
    else
        echo "❌ Failed to create KIND cluster (exit code: $CREATE_EXIT_CODE)" && date
        collect_failure_diagnostics
        exit 1
    fi
}

setup_cluster() {
    echo "Setting up KIND cluster addons and configuration" && date
    local setup_log="$LOG_DIR/kind-setup.log"
    
    {
        echo "=== KIND CLUSTER SETUP STARTING ==="
        date
        
        # Set up kubectl context
        echo "Setting up kubectl context..."
        kubectl config use-context "kind-$CLUSTER_NAME"
        kubectl config current-context
        
        # Export kubeconfig for GitHub Actions
        if [[ -n "${GITHUB_ENV:-}" ]]; then
            echo "KUBECONFIG=$HOME/.kube/config" >> "$GITHUB_ENV"
            echo "KUBECONFIG exported for GitHub Actions"
        fi
        
        # Wait for cluster readiness (KIND is usually faster)
        echo "Waiting for cluster to be ready" && date
        
        echo "Waiting for nodes..."
        kubectl wait --for=condition=Ready node --all --timeout=180s
        
        echo "Waiting for DNS pods..."
        kubectl wait --for=condition=Ready -n kube-system pod -l k8s-app=kube-dns --timeout=120s
        
        # Install basic storage class for testing
        echo "Setting up local storage..."
        kubectl apply -f - << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF
        
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
        
        echo "=== KIND CLUSTER SETUP COMPLETED ==="
        date
        
    } | tee -a "$setup_log"
}

destroy_cluster() {
    echo "Destroying KIND cluster: $CLUSTER_NAME" && date
    kind delete cluster --name "$CLUSTER_NAME" || true
    docker system prune -f || true
    echo "✅ KIND cluster $CLUSTER_NAME destroyed" && date
}

start_resource_monitoring() {
    echo "Starting resource monitoring for KIND cluster creation..." && date
    RESOURCE_LOG="$LOG_DIR/kind-resource-monitoring-$(date +%s).log"
    
    while true; do
        echo "=== RESOURCE SNAPSHOT $(date) ===" >> "$RESOURCE_LOG"
        echo "Memory:" >> "$RESOURCE_LOG"
        free -h >> "$RESOURCE_LOG" 2>/dev/null || true
        echo "Docker containers:" >> "$RESOURCE_LOG"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" >> "$RESOURCE_LOG" 2>/dev/null || true
        echo "KIND containers:" >> "$RESOURCE_LOG"
        docker ps --filter "label=io.x-k8s.kind.cluster=$CLUSTER_NAME" >> "$RESOURCE_LOG" 2>/dev/null || true
        echo "" >> "$RESOURCE_LOG"
        sleep 5  # Faster monitoring for KIND
    done
}

collect_pre_creation_diagnostics() {
    local diag_file="$LOG_DIR/kind-pre-creation-diagnostics.log"
    echo "Collecting KIND pre-creation diagnostics to $diag_file" && date
    
    {
        echo "=== KIND PRE-CREATION DIAGNOSTICS ==="
        date
        
        echo "=== DOCKER STATUS ==="
        docker version || true
        docker info || true
        docker ps -a || true
        
        echo "=== KIND STATUS ==="
        kind version || true
        kind get clusters || true
        
        echo "=== SYSTEM RESOURCES ==="
        free -h || true
        df -h || true
        uptime || true
        
    } > "$diag_file" 2>&1
}

collect_post_creation_diagnostics() {
    local diag_file="$LOG_DIR/kind-post-creation-diagnostics.log"
    echo "Collecting KIND post-creation diagnostics to $diag_file" && date
    
    {
        echo "=== KIND POST-CREATION DIAGNOSTICS ==="
        date
        
        echo "=== KIND CLUSTER STATUS ==="
        kind get clusters || true
        kubectl get nodes -o wide || true
        kubectl get pods -A || true
        
        echo "=== KIND CONTAINER STATUS ==="
        docker ps --filter "label=io.x-k8s.kind.cluster=$CLUSTER_NAME" || true
        
        echo "=== CLUSTER CONNECTIVITY ==="
        kubectl cluster-info || true
        kubectl get svc -A || true
        
    } > "$diag_file" 2>&1
}

collect_failure_diagnostics() {
    local diag_file="$LOG_DIR/kind-failure-diagnostics.log"
    echo "Collecting KIND failure diagnostics to $diag_file" && date
    
    {
        echo "=== KIND FAILURE DIAGNOSTICS ==="
        date
        
        echo "=== KIND CLUSTER STATUS ==="
        kind get clusters || true
        
        echo "=== DOCKER CONTAINER LOGS ==="
        for container in $(docker ps -a --filter "label=io.x-k8s.kind.cluster=$CLUSTER_NAME" --format "{{.Names}}"); do
            echo "--- Container $container logs ---"
            docker logs --tail=50 "$container" 2>&1 || true
        done
        
        echo "=== DOCKER SYSTEM STATUS ==="
        docker ps -a || true
        docker system df || true
        
        echo "=== SYSTEM STATUS ==="
        free -h || true
        df -h || true
        uptime || true
        
    } > "$diag_file" 2>&1
}

status_cluster() {
    echo "KIND cluster status: $CLUSTER_NAME" && date
    if kind get clusters | grep -q "$CLUSTER_NAME"; then
        kubectl get nodes -o wide
        kubectl get pods -A
        echo "KIND containers:"
        docker ps --filter "label=io.x-k8s.kind.cluster=$CLUSTER_NAME"
    else
        echo "KIND cluster $CLUSTER_NAME is not running"
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
        echo "  KUBERNETES_VERSION=${KUBERNETES_VERSION}"
        exit 1
        ;;
esac

echo "=== KIND Cluster Management Complete - Action: $ACTION ===" && date