#!/usr/bin/env bash
# scripts/manage_hybrid_cluster.sh - Hybrid cluster management: KIND (primary) + minikube (fallback)
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/hybrid-cluster-management.log"
exec > >(tee -a "$LOG_FILE") 2>&1

ACTION=${1:-"create"}
CLUSTER_NAME=${CLUSTER_NAME:-"ci-cluster"}
CLUSTER_TYPE_FILE="/tmp/cluster-type-$CLUSTER_NAME"

echo "=== Hybrid Cluster Management - Action: $ACTION ===" && date

# Strategy: Try KIND first (faster, more CI-friendly), fallback to minikube if needed
PREFERRED_STRATEGY=${PREFERRED_STRATEGY:-"kind"}  # kind or minikube
FALLBACK_STRATEGY=${FALLBACK_STRATEGY:-"minikube"} # minikube or kind

create_cluster() {
    echo "Creating cluster with hybrid strategy: $PREFERRED_STRATEGY -> $FALLBACK_STRATEGY" && date
    
    # Try primary strategy first
    if try_create_with_strategy "$PREFERRED_STRATEGY"; then
        echo "✅ Cluster created successfully with $PREFERRED_STRATEGY" && date
        echo "$PREFERRED_STRATEGY" > "$CLUSTER_TYPE_FILE"
        return 0
    fi
    
    echo "⚠️  Primary strategy $PREFERRED_STRATEGY failed, trying fallback $FALLBACK_STRATEGY" && date
    
    # Try fallback strategy
    if try_create_with_strategy "$FALLBACK_STRATEGY"; then
        echo "✅ Cluster created successfully with $FALLBACK_STRATEGY (fallback)" && date
        echo "$FALLBACK_STRATEGY" > "$CLUSTER_TYPE_FILE"
        return 0
    fi
    
    echo "❌ Both strategies failed: $PREFERRED_STRATEGY and $FALLBACK_STRATEGY" && date
    collect_final_failure_diagnostics
    exit 1
}

try_create_with_strategy() {
    local strategy=$1
    echo "=== TRYING CLUSTER CREATION WITH $strategy ===" && date
    
    case "$strategy" in
        "kind")
            # Try KIND with timeout
            echo "Attempting KIND cluster creation..."
            if timeout 600 scripts/manage_kind_cluster.sh create; then
                echo "✅ KIND cluster creation successful"
                return 0
            else
                echo "❌ KIND cluster creation failed or timed out"
                scripts/manage_kind_cluster.sh destroy || true
                return 1
            fi
            ;;
        "minikube")
            # Try minikube with more aggressive timeout
            echo "Attempting minikube cluster creation..."
            if timeout 1200 scripts/manage_ci_cluster.sh create; then
                echo "✅ Minikube cluster creation successful"
                return 0
            else
                echo "❌ Minikube cluster creation failed or timed out"
                scripts/manage_ci_cluster.sh destroy || true
                return 1
            fi
            ;;
        *)
            echo "❌ Unknown strategy: $strategy"
            return 1
            ;;
    esac
}

destroy_cluster() {
    echo "Destroying hybrid cluster: $CLUSTER_NAME" && date
    
    # Determine which type of cluster was created
    if [[ -f "$CLUSTER_TYPE_FILE" ]]; then
        CLUSTER_TYPE=$(cat "$CLUSTER_TYPE_FILE")
        echo "Destroying $CLUSTER_TYPE cluster based on stored type"
        
        case "$CLUSTER_TYPE" in
            "kind")
                scripts/manage_kind_cluster.sh destroy
                ;;
            "minikube")
                scripts/manage_ci_cluster.sh destroy
                ;;
            *)
                echo "Unknown cluster type: $CLUSTER_TYPE, trying both destruction methods"
                scripts/manage_kind_cluster.sh destroy || true
                scripts/manage_ci_cluster.sh destroy || true
                ;;
        esac
        rm -f "$CLUSTER_TYPE_FILE"
    else
        echo "No cluster type file found, trying both destruction methods"
        scripts/manage_kind_cluster.sh destroy || true
        scripts/manage_ci_cluster.sh destroy || true
    fi
    
    # Clean up Docker resources
    docker system prune -f || true
    echo "✅ Hybrid cluster destroyed" && date
}

status_cluster() {
    echo "Hybrid cluster status: $CLUSTER_NAME" && date
    
    if [[ -f "$CLUSTER_TYPE_FILE" ]]; then
        CLUSTER_TYPE=$(cat "$CLUSTER_TYPE_FILE")
        echo "Active cluster type: $CLUSTER_TYPE"
        
        case "$CLUSTER_TYPE" in
            "kind")
                scripts/manage_kind_cluster.sh status
                ;;
            "minikube")
                scripts/manage_ci_cluster.sh status
                ;;
            *)
                echo "Unknown cluster type: $CLUSTER_TYPE"
                ;;
        esac
    else
        echo "No active cluster found"
        # Try to detect existing clusters
        if kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
            echo "Found KIND cluster:"
            scripts/manage_kind_cluster.sh status
        elif minikube status -p "$CLUSTER_NAME" >/dev/null 2>&1; then
            echo "Found minikube cluster:"
            scripts/manage_ci_cluster.sh status
        else
            echo "No clusters found"
        fi
    fi
}

collect_final_failure_diagnostics() {
    local diag_file="$LOG_DIR/hybrid-final-failure-diagnostics.log"
    echo "Collecting final failure diagnostics to $diag_file" && date
    
    {
        echo "=== HYBRID CLUSTER FINAL FAILURE ANALYSIS ==="
        date
        
        echo "=== STRATEGIES ATTEMPTED ==="
        echo "Primary: $PREFERRED_STRATEGY"
        echo "Fallback: $FALLBACK_STRATEGY"
        
        echo "=== KIND STATUS ==="
        kind get clusters || true
        kind version || true
        
        echo "=== MINIKUBE STATUS ==="
        minikube profile list || true
        minikube version --short || true
        
        echo "=== DOCKER STATUS ==="
        docker ps -a || true
        docker system df || true
        docker version || true
        
        echo "=== SYSTEM RESOURCES ==="
        free -h || true
        df -h || true
        uptime || true
        ps aux --sort=-%mem | head -10 || true
        
        echo "=== RECENT LOGS ==="
        echo "--- KIND logs ---"
        ls -la "$LOG_DIR"/kind-* 2>/dev/null || echo "No KIND logs found"
        echo "--- Minikube logs ---"
        ls -la "$LOG_DIR"/minikube-* 2>/dev/null || echo "No minikube logs found"
        
    } > "$diag_file" 2>&1
}

# Enhanced version for CI environments
if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "CI environment detected - optimizing strategy for GitHub Actions"
    # KIND is generally more reliable in CI environments
    PREFERRED_STRATEGY="kind"
    FALLBACK_STRATEGY="minikube"
    echo "Strategy: KIND (primary) -> minikube (fallback)"
fi

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
    *)
        echo "Usage: $0 {create|destroy|status}"
        echo "Environment variables:"
        echo "  CLUSTER_NAME=${CLUSTER_NAME}"
        echo "  PREFERRED_STRATEGY=${PREFERRED_STRATEGY}"
        echo "  FALLBACK_STRATEGY=${FALLBACK_STRATEGY}"
        exit 1
        ;;
esac

echo "=== Hybrid Cluster Management Complete - Action: $ACTION ===" && date