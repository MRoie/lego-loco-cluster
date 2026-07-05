#!/bin/bash
# Development Cycle Deploy Script for Kubernetes Discovery Issue Resolution
# This script provides comprehensive cleanup and deployment cycle for systematic debugging

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_NAME="loco-backend"
IMAGE_TAG="latest"
NAMESPACE="loco"
HELM_RELEASE="loco"
HELM_CHART="./helm/loco-chart"
BUILD_CONTEXT="./backend"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

log_section() {
    echo -e "\n${BLUE}==== $1 ====${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    # Check minikube
    if ! command -v minikube &> /dev/null; then
        log_error "minikube is not installed or not in PATH"
        exit 1
    fi
    
    # Check docker
    if ! command -v docker &> /dev/null; then
        log_error "docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    log_success "All prerequisites available"
}

# Comprehensive cleanup function
cleanup_all() {
    log_section "Comprehensive Cleanup"
    
    # Comprehensive Helm cleanup - check for multiple release names
    log_info "Cleaning up all Helm releases..."
    
    # Try common release names that might conflict
    for release in "loco-cluster" "loco" "lego-loco" "emulator"; do
        if helm list -n "$NAMESPACE" | grep -q "$release"; then
            log_info "Uninstalling Helm release: $release"
            helm uninstall "$release" -n "$NAMESPACE" 2>/dev/null || log_warning "Failed to uninstall $release"
        fi
    done
    
    # Also check default namespace for releases
    for release in "loco-cluster" "loco" "lego-loco" "emulator"; do
        if helm list | grep -q "$release"; then
            log_info "Uninstalling Helm release in default namespace: $release"
            helm uninstall "$release" 2>/dev/null || log_warning "Failed to uninstall $release from default namespace"
        fi
    done
    
    # Clean up persistent volumes that might conflict
    log_info "Cleaning up persistent volumes..."
    kubectl get pv | grep -E "(win98|loco|emulator)" | awk '{print $1}' | while read pv; do
        if [[ -n "$pv" && "$pv" != "NAME" ]]; then
            log_info "Deleting persistent volume: $pv"
            kubectl delete pv "$pv" --ignore-not-found=true || log_warning "Failed to delete PV $pv"
        fi
    done
    
    # Clean up persistent volume claims
    log_info "Cleaning up persistent volume claims in namespace $NAMESPACE..."
    kubectl delete pvc --all -n "$NAMESPACE" --ignore-not-found=true || log_warning "Failed to delete PVCs"
    
    # Kubernetes namespace cleanup
    log_info "Cleaning up Kubernetes namespace..."
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
    
    # Wait for namespace deletion
    log_info "Waiting for namespace deletion..."
    while kubectl get namespace "$NAMESPACE" &> /dev/null; do
        log_info "Waiting for namespace $NAMESPACE to be deleted..."
        sleep 2
    done
    
    # Additional cleanup for stuck resources
    log_info "Force cleaning any stuck resources..."
    kubectl get all --all-namespaces | grep -E "(loco|emulator)" | awk '{print $1 "/" $2}' | while read resource; do
        if [[ -n "$resource" && "$resource" != "/" ]]; then
            log_info "Force deleting stuck resource: $resource"
            kubectl delete "$resource" --force --grace-period=0 2>/dev/null || log_warning "Failed to force delete $resource"
        fi
    done
    
    # Docker cleanup
    log_info "Cleaning up Docker containers and images..."
    docker container prune -f || log_warning "Docker container prune failed"
    docker image prune -f || log_warning "Docker image prune failed"
    docker system prune -f || log_warning "Docker system prune failed"
    
    # Remove specific images
    log_info "Removing specific backend images..."
    docker rmi "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || log_warning "Image ${IMAGE_NAME}:${IMAGE_TAG} not found"
    docker rmi "$(docker images -q ${IMAGE_NAME} 2>/dev/null)" 2>/dev/null || log_warning "No ${IMAGE_NAME} images found"
    
    # Minikube cleanup
    log_info "Cleaning up Minikube..."
    
    # Remove images from minikube
    minikube image rm "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || log_warning "Image not found in minikube"
    
    # Clean minikube docker cache
    log_info "Cleaning minikube docker cache..."
    minikube ssh -- "docker container prune -f" 2>/dev/null || log_warning "Minikube container prune failed"
    minikube ssh -- "docker image prune -f" 2>/dev/null || log_warning "Minikube image prune failed"
    minikube ssh -- "docker system prune -af" 2>/dev/null || log_warning "Minikube system prune failed"
    
    # Final cleanup - remove any orphaned persistent volumes
    log_info "Final cleanup of orphaned persistent volumes..."
    sleep 5  # Wait for namespace deletion to propagate
    kubectl get pv | grep -E "(Available|Released|Failed)" | grep -E "(win98|loco|emulator)" | awk '{print $1}' | while read pv; do
        if [[ -n "$pv" && "$pv" != "NAME" ]]; then
            log_info "Cleaning up orphaned PV: $pv"
            kubectl patch pv "$pv" -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
            kubectl delete pv "$pv" --ignore-not-found=true 2>/dev/null || true
        fi
    done
    
    # Check if minikube is running, if not start it
    if ! minikube status | grep -q "Running"; then
        log_info "Starting minikube..."
        minikube start --driver=docker --memory=4096 --cpus=2
    fi
    
    log_success "Comprehensive cleanup completed"
}

# Targeted cleanup function - focuses on backend components only
cleanup_backend_only() {
    log_section "Targeted Backend Cleanup"
    
    # Only cleanup the specific Helm release
    log_info "Cleaning up Helm release: $HELM_RELEASE"
    helm uninstall "$HELM_RELEASE" -n "$NAMESPACE" 2>/dev/null || log_warning "Helm release $HELM_RELEASE not found"
    
    # Only delete backend-related pods/deployments (keep emulators running)
    log_info "Cleaning up backend deployments..."
    kubectl delete deployment -l app.kubernetes.io/component=backend -n "$NAMESPACE" --ignore-not-found=true || log_warning "No backend deployments found"
    
    # Delete backend services
    log_info "Cleaning up backend services..."
    kubectl delete service -l app.kubernetes.io/component=backend -n "$NAMESPACE" --ignore-not-found=true || log_warning "No backend services found"
    
    # Delete backend configmaps and secrets
    log_info "Cleaning up backend configs..."
    kubectl delete configmap -l app.kubernetes.io/component=backend -n "$NAMESPACE" --ignore-not-found=true || log_warning "No backend configmaps found"
    kubectl delete secret -l app.kubernetes.io/component=backend -n "$NAMESPACE" --ignore-not-found=true || log_warning "No backend secrets found"
    
    # Wait for pods to terminate
    log_info "Waiting for backend pods to terminate..."
    while kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=backend 2>/dev/null | grep -q "backend"; do
        log_info "Waiting for backend pods to terminate..."
        sleep 2
    done
    
    # Docker cleanup - only backend images
    log_info "Cleaning up backend Docker images..."
    docker rmi "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || log_warning "Image ${IMAGE_NAME}:${IMAGE_TAG} not found"
    docker rmi "$(docker images -q ${IMAGE_NAME} 2>/dev/null)" 2>/dev/null || log_warning "No ${IMAGE_NAME} images found"
    
    # Remove backend image from minikube
    log_info "Removing backend image from minikube..."
    minikube image rm "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || log_warning "Image not found in minikube"
    
    log_success "Targeted backend cleanup completed"
}

# Build Docker image with verification
build_image() {
    log_section "Building Docker Image"
    
    cd "$PROJECT_ROOT"
    
    # Verify source files
    log_info "Verifying source files..."
    if [[ ! -f "$BUILD_CONTEXT/services/kubernetesDiscovery.js" ]]; then
        log_error "kubernetesDiscovery.js not found in $BUILD_CONTEXT/services/"
        exit 1
    fi
    
    # Show current API calls in source for verification
    log_info "Current API calls in source:"
    grep -n "await this.k8sApi" "$BUILD_CONTEXT/services/kubernetesDiscovery.js" || log_warning "No API calls found"
    
    # Build with no cache and verbose output
    log_info "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
    docker build \
        --no-cache \
        --progress=plain \
        --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
        "$BUILD_CONTEXT"
    
    # Verify build
    if docker images | grep -q "${IMAGE_NAME}.*${IMAGE_TAG}"; then
        log_success "Docker image built successfully"
    else
        log_error "Docker image build failed"
        exit 1
    fi
    
    # Load image into minikube
    log_info "Loading image into minikube..."
    minikube image load "${IMAGE_NAME}:${IMAGE_TAG}"
    
    # Verify image in minikube
    if minikube image ls | grep -q "${IMAGE_NAME}:${IMAGE_TAG}"; then
        log_success "Image loaded into minikube successfully"
    else
        log_error "Failed to load image into minikube"
        exit 1
    fi
}

# Deploy to Kubernetes
deploy_to_k8s() {
    log_section "Deploying to Kubernetes"
    
    cd "$PROJECT_ROOT"
    
    # Create namespace
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" || log_warning "Namespace may already exist"
    
    # Pre-deployment validation
    log_info "Validating deployment prerequisites..."
    
    # Check for any remaining conflicting resources
    if kubectl get pv | grep -q "win98-disk-pv"; then
        log_warning "Found existing persistent volume win98-disk-pv, attempting cleanup..."
        kubectl delete pv win98-disk-pv --ignore-not-found=true || log_warning "Could not delete existing PV"
        sleep 2
    fi
    
    # Deploy with Helm - using simple image string format that matches chart structure
    log_info "Deploying with Helm..."
    
    # Create a temporary values file that matches the chart's structure
    cat > /tmp/helm-values.yaml << EOF
# Set empty imageRepo to use full image paths
imageRepo: ""

backend:
  image: ${IMAGE_NAME}
  tag: ${IMAGE_TAG}
  env:
    ALLOW_EMPTY_DISCOVERY: "false"
    FORCE_CONSOLE_LOGGING: "true" 
    LOG_LEVEL: "debug"
    KUBERNETES_NAMESPACE: "${NAMESPACE}"

# Use full image paths for other components to override imageRepo
frontend:
  image: ghcr.io/mroie/loco-frontend
  tag: latest

vr:
  image: ghcr.io/mroie/loco-frontend
  tag: latest

emulator:
  image: ghcr.io/mroie/lego-loco-cluster/win98-softgpu
  tag: latest

nfs:
  image: itsthenetwork/nfs-server-alpine:latest
EOF
    
    # Deploy with the values file
    if helm install "$HELM_RELEASE" "$HELM_CHART" \
        --namespace "$NAMESPACE" \
        --values /tmp/helm-values.yaml \
        --wait \
        --timeout=5m; then
        log_success "Helm deployment completed successfully"
    else
        log_error "Helm deployment failed"
        
        # Show debug information
        log_info "Helm status for debugging:"
        helm status "$HELM_RELEASE" -n "$NAMESPACE" || true
        
        log_info "Kubernetes events for debugging:"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
        
        # Cleanup the failed deployment
        helm uninstall "$HELM_RELEASE" -n "$NAMESPACE" 2>/dev/null || true
        rm -f /tmp/helm-values.yaml
        exit 1
    fi
    
    # Cleanup temporary file
    rm -f /tmp/helm-values.yaml
    
    log_success "Deployment completed"
}

# Verify deployment
verify_deployment() {
    log_section "Verifying Deployment"
    
    # Wait for pods to be ready
    log_info "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=loco -n "$NAMESPACE" --timeout=300s
    
    # Show pod status
    log_info "Pod status:"
    kubectl get pods -n "$NAMESPACE" -o wide
    
    # Show backend logs
    log_info "Backend logs (last 20 lines):"
    BACKEND_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=backend -o jsonpath='{.items[0].metadata.name}')
    kubectl logs "$BACKEND_POD" -n "$NAMESPACE" --tail=20
    
    # Check for specific error
    log_info "Checking for API parameter error..."
    if kubectl logs "$BACKEND_POD" -n "$NAMESPACE" | grep -q "Required parameter namespace was null or undefined"; then
        log_error "❌ API parameter error still present!"
        return 1
    else
        log_success "✅ No API parameter error found"
    fi
    
    # Test API connectivity
    log_info "Testing API connectivity..."
    kubectl port-forward -n "$NAMESPACE" "service/loco-backend" 3001:3001 &
    PORT_FORWARD_PID=$!
    sleep 5
    
    # Test health endpoint
    if curl -f http://localhost:3001/health &> /dev/null; then
        log_success "✅ Health endpoint accessible"
    else
        log_warning "⚠️ Health endpoint not accessible"
    fi
    
    # Test instances endpoint
    if curl -f http://localhost:3001/api/instances &> /dev/null; then
        log_success "✅ Instances endpoint accessible"
        # Show instance discovery results
        log_info "Instance discovery results:"
        curl -s http://localhost:3001/api/instances | head -20
    else
        log_warning "⚠️ Instances endpoint not accessible"
    fi
    
    # Cleanup port forward
    kill $PORT_FORWARD_PID 2>/dev/null || true
}

# Show debugging information
show_debug_info() {
    log_section "Debug Information"
    
    # Show image information
    log_info "Docker images:"
    docker images | grep -E "(${IMAGE_NAME}|REPOSITORY)" || log_warning "No matching images"
    
    # Show minikube images
    log_info "Minikube images:"
    minikube image ls | grep -E "(${IMAGE_NAME}|IMAGE)" || log_warning "No matching images in minikube"
    
    # Show Helm status
    log_info "Helm status:"
    helm status "$HELM_RELEASE" -n "$NAMESPACE" || log_warning "Helm release not found"
    
    # Show file verification in running container
    if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=backend &> /dev/null; then
        BACKEND_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=backend -o jsonpath='{.items[0].metadata.name}')
        log_info "Verifying file in running container:"
        kubectl exec "$BACKEND_POD" -n "$NAMESPACE" -- grep -n "await this.k8sApi" /app/services/kubernetesDiscovery.js || log_warning "File verification failed"
    fi
}

# Main execution
main() {
    log_section "Development Cycle Deploy Script"
    log_info "Target: ${IMAGE_NAME}:${IMAGE_TAG} in namespace ${NAMESPACE}"
    log_info "Project root: $PROJECT_ROOT"
    
    # Parse command line arguments
    SKIP_CLEANUP=false
    VERIFY_ONLY=false
    DEBUG_ONLY=false
    CLEANUP_ONLY=false
    BACKEND_ONLY=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-cleanup)
                SKIP_CLEANUP=true
                shift
                ;;
            --verify-only)
                VERIFY_ONLY=true
                shift
                ;;
            --debug-only)
                DEBUG_ONLY=true
                shift
                ;;
            --cleanup-only)
                CLEANUP_ONLY=true
                shift
                ;;
            --backend-only)
                BACKEND_ONLY=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--skip-cleanup] [--verify-only] [--debug-only] [--cleanup-only] [--backend-only]"
                echo "  --skip-cleanup   Skip the comprehensive cleanup step"
                echo "  --verify-only    Only run verification steps"
                echo "  --debug-only     Only show debug information"
                echo "  --cleanup-only   Only run comprehensive cleanup"
                echo "  --backend-only   Use targeted backend cleanup (faster, keeps emulators)"
                exit 0
                ;;
            *)
                log_error "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute based on mode
    if [[ "$DEBUG_ONLY" == "true" ]]; then
        check_prerequisites
        show_debug_info
        exit 0
    fi
    
    if [[ "$VERIFY_ONLY" == "true" ]]; then
        check_prerequisites
        verify_deployment
        show_debug_info
        exit 0
    fi
    
    if [[ "$CLEANUP_ONLY" == "true" ]]; then
        check_prerequisites
        cleanup_all
        log_success "🧹 Cleanup completed successfully!"
        exit 0
    fi
    
    # Full cycle
    check_prerequisites
    
    if [[ "$SKIP_CLEANUP" != "true" ]]; then
        if [[ "$BACKEND_ONLY" == "true" ]]; then
            cleanup_backend_only
        else
            cleanup_all
        fi
    fi
    
    build_image
    deploy_to_k8s
    verify_deployment
    show_debug_info
    
    log_section "Development Cycle Complete"
    log_success "🎯 Development cycle completed successfully!"
    log_info "🔍 Check the debug information above for any issues"
    log_info "📝 Update RCA_KUBERNETES_DISCOVERY.md with results"
    log_info "📝 Update RCA_KUBERNETES_DISCOVERY.md with results"
}

# Run main function with all arguments
main "$@"
