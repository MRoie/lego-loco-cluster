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
    
    # Helm cleanup
    log_info "Cleaning up Helm releases..."
    helm uninstall loco-cluster -n "$NAMESPACE" 2>/dev/null || log_warning "Helm release not found"
    
    # Kubernetes namespace cleanup
    log_info "Cleaning up Kubernetes namespace..."
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
    
    # Wait for namespace deletion
    log_info "Waiting for namespace deletion..."
    while kubectl get namespace "$NAMESPACE" &> /dev/null; do
        log_info "Waiting for namespace $NAMESPACE to be deleted..."
        sleep 2
    done
    
    # Docker cleanup
    log_info "Cleaning up Docker containers and images..."
    docker container prune -f || log_warning "Docker container prune failed"
    docker image prune -f || log_warning "Docker image prune failed"
    docker system prune -f || log_warning "Docker system prune failed"
    
    # Remove specific images
    log_info "Removing specific backend images..."
    docker rmi "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || log_warning "Image ${IMAGE_NAME}:${IMAGE_TAG} not found"
    docker rmi "$(docker images -q ${IMAGE_NAME})" 2>/dev/null || log_warning "No ${IMAGE_NAME} images found"
    
    # Minikube cleanup
    log_info "Cleaning up Minikube..."
    
    # Remove images from minikube
    minikube image rm "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || log_warning "Image not found in minikube"
    
    # Clean minikube docker cache
    log_info "Cleaning minikube docker cache..."
    minikube ssh -- "docker container prune -f" 2>/dev/null || log_warning "Minikube container prune failed"
    minikube ssh -- "docker image prune -f" 2>/dev/null || log_warning "Minikube image prune failed"
    minikube ssh -- "docker system prune -af" 2>/dev/null || log_warning "Minikube system prune failed"
    
    # Check if minikube is running, if not start it
    if ! minikube status | grep -q "Running"; then
        log_info "Starting minikube..."
        minikube start --driver=docker --memory=4096 --cpus=2
    fi
    
    log_success "Comprehensive cleanup completed"
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
    
    # Deploy with Helm
    log_info "Deploying with Helm..."
    helm install loco-cluster "$HELM_CHART" \
        --namespace "$NAMESPACE" \
        --set backend.image.repository="$IMAGE_NAME" \
        --set backend.image.tag="$IMAGE_TAG" \
        --set backend.image.pullPolicy="Always" \
        --set backend.env.ALLOW_EMPTY_DISCOVERY="false" \
        --set backend.env.FORCE_CONSOLE_LOGGING="true" \
        --set backend.env.LOG_LEVEL="debug" \
        --wait \
        --timeout=5m
    
    log_success "Deployment completed"
}

# Verify deployment
verify_deployment() {
    log_section "Verifying Deployment"
    
    # Wait for pods to be ready
    log_info "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=loco-cluster -n "$NAMESPACE" --timeout=300s
    
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
    kubectl port-forward -n "$NAMESPACE" "service/loco-cluster-backend" 3001:3001 &
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
    helm status loco-cluster -n "$NAMESPACE" || log_warning "Helm release not found"
    
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
            --help)
                echo "Usage: $0 [--skip-cleanup] [--verify-only] [--debug-only]"
                echo "  --skip-cleanup  Skip the comprehensive cleanup step"
                echo "  --verify-only   Only run verification steps"
                echo "  --debug-only    Only show debug information"
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
    
    # Full cycle
    check_prerequisites
    
    if [[ "$SKIP_CLEANUP" != "true" ]]; then
        cleanup_all
    fi
    
    build_image
    deploy_to_k8s
    verify_deployment
    show_debug_info
    
    log_section "Development Cycle Complete"
    log_success "🎯 Development cycle completed successfully!"
    log_info "🔍 Check the debug information above for any issues"
    log_info "📝 Update RCA_KUBERNETES_DISCOVERY.md with results"
}

# Run main function with all arguments
main "$@"
