#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="loco"
CHART_PATH="helm/loco-chart"
CLUSTER_NAME="minikube"

# Function to log messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if minikube is running
check_minikube() {
    if ! minikube status &> /dev/null; then
        log_error "Minikube is not running. Please start minikube first."
        exit 1
    fi
    log_success "Minikube is running"
}

# Function to deploy with hostPath storage (Option 1)
deploy_hostpath() {
    log_info "Deploying with HostPath storage strategy (Option 1)..."
    
    # Create shared directory on minikube host
    log_info "Creating shared directory on minikube host..."
    minikube ssh "sudo mkdir -p /tmp/loco-art-shared && sudo chmod 777 /tmp/loco-art-shared"
    
    # Deploy with hostPath configuration
    helm upgrade --install loco $CHART_PATH \
        --namespace $NAMESPACE \
        --create-namespace \
        -f $CHART_PATH/values-minikube-hostpath.yaml \
        --wait --timeout=300s
    
    log_success "HostPath deployment completed"
}

# Function to deploy with hybrid storage (Option 8)
deploy_hybrid() {
    log_info "Deploying with Hybrid storage strategy (Option 8)..."
    
    # Deploy with hybrid configuration
    helm upgrade --install loco $CHART_PATH \
        --namespace $NAMESPACE \
        --create-namespace \
        -f $CHART_PATH/values-minikube-hybrid.yaml \
        --wait --timeout=300s
    
    log_success "Hybrid deployment completed"
}

# Function to deploy with default NFS storage
deploy_nfs() {
    log_info "Deploying with default NFS storage..."
    
    # Deploy with default configuration
    helm upgrade --install loco $CHART_PATH \
        --namespace $NAMESPACE \
        --create-namespace \
        -f $CHART_PATH/values-minikube.yaml \
        --wait --timeout=300s
    
    log_success "NFS deployment completed"
}

# Function to show deployment status
show_status() {
    log_info "Checking deployment status..."
    
    echo ""
    echo "=== Pod Status ==="
    kubectl get pods -n $NAMESPACE
    
    echo ""
    echo "=== Services ==="
    kubectl get services -n $NAMESPACE
    
    echo ""
    echo "=== PVCs ==="
    kubectl get pvc -n $NAMESPACE
    
    echo ""
    echo "=== Storage Strategy ==="
    if kubectl get configmap -n $NAMESPACE loco-storage-init &> /dev/null; then
        echo "✅ HostPath storage enabled"
    elif kubectl get configmap -n $NAMESPACE loco-hybrid-storage &> /dev/null; then
        echo "✅ Hybrid storage enabled"
    else
        echo "✅ NFS storage enabled"
    fi
}

# Function to show troubleshooting commands
show_troubleshooting() {
    echo ""
    echo "=== Troubleshooting Commands ==="
    echo "Check pod logs:"
    echo "  kubectl logs -f deployment/loco-loco-frontend -n $NAMESPACE"
    echo "  kubectl logs -f deployment/loco-loco-backend -n $NAMESPACE"
    echo "  kubectl logs -f statefulset/loco-loco-emulator -n $NAMESPACE"
    echo ""
    echo "Check storage:"
    echo "  kubectl describe pvc -n $NAMESPACE"
    echo "  kubectl get pv"
    echo ""
    echo "Check NFS server (if enabled):"
    echo "  kubectl logs -f deployment/nfs-server -n $NAMESPACE"
    echo ""
    echo "Access services:"
    echo "  minikube service loco-loco-frontend -n $NAMESPACE"
    echo "  minikube service loco-loco-backend -n $NAMESPACE"
}

# Main script
main() {
    log_info "Starting storage options deployment..."
    
    # Check if minikube is running
    check_minikube
    
    # Parse command line arguments
    STORAGE_OPTION=${1:-"hostpath"}
    
    case $STORAGE_OPTION in
        "hostpath"|"1")
            deploy_hostpath
            ;;
        "hybrid"|"8")
            deploy_hybrid
            ;;
        "nfs"|"default")
            deploy_nfs
            ;;
        *)
            log_error "Invalid storage option: $STORAGE_OPTION"
            echo "Usage: $0 [hostpath|hybrid|nfs]"
            echo "  hostpath - Use HostPath direct mounts (Option 1)"
            echo "  hybrid   - Use Hybrid storage strategy (Option 8)"
            echo "  nfs      - Use default NFS storage"
            exit 1
            ;;
    esac
    
    # Show status
    show_status
    
    # Show troubleshooting
    show_troubleshooting
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@" 