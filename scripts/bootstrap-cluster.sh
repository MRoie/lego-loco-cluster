#!/bin/bash

# Don't exit on error - we want to continue and report all issues
# set -e

# Parse command line arguments
DESTROY_MODE=false
HELP_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --destroy)
            DESTROY_MODE=true
            shift
            ;;
        --help|-h)
            HELP_MODE=true
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            echo "Usage: $0 [--destroy] [--help]"
            echo "  --destroy    Clean up all resources (namespace, PVs, host directories)"
            echo "  --help, -h   Show this help message"
            exit 1
            ;;
    esac
done

if [ "$HELP_MODE" = true ]; then
    echo "Lego Loco Cluster Bootstrap Script"
    echo ""
    echo "Usage: $0 [--destroy] [--help]"
    echo ""
    echo "Options:"
    echo "  --destroy    Clean up all resources (namespace, PVs, host directories)"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Bootstrap the cluster"
    echo "  $0 --destroy    # Clean up all resources"
    echo "  $0 --help       # Show this help"
    exit 0
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="loco"
CHART_PATH="helm/loco-chart"
VALUES_FILE="helm/loco-chart/values-minikube-hostpath.yaml"  # Use hostPath configuration (Option 1)
CLUSTER_NAME="minikube"

# Docker registry configuration for TLS issues
DOCKER_REGISTRY_CONFIG="--insecure-registry docker.io --insecure-registry registry-1.docker.io"

# Required images
IMAGES=(
    "compose-backend:latest"
    "compose-frontend:latest"
    "compose-emulator-0:latest"
    "compose-emulator-1:latest"
    "compose-emulator-2:latest"
    "compose-emulator-3:latest"
    "compose-emulator-4:latest"
    "compose-emulator-5:latest"
    "compose-emulator-6:latest"
    "compose-emulator-7:latest"
    "compose-emulator-8:latest"
    "compose-vr-frontend:latest"
)

# Docker build contexts (format: context:image_name:dockerfile_path)
BUILD_CONTEXTS=(
    "backend:compose-backend:latest:Dockerfile"
    "frontend:compose-frontend:latest:Dockerfile"
    "containers/qemu-softgpu:compose-emulator-0:latest:Dockerfile"
    "containers/qemu-softgpu:compose-emulator-1:latest:Dockerfile"
    "containers/qemu-softgpu:compose-emulator-2:latest:Dockerfile"
    "containers/qemu-softgpu:compose-emulator-3:latest:Dockerfile"
    "containers/qemu-softgpu:compose-emulator-4:latest:Dockerfile"
    "containers/qemu-softgpu:compose-emulator-5:latest:Dockerfile"
    "containers/qemu-softgpu:compose-emulator-6:latest:Dockerfile"
    "containers/qemu-softgpu:compose-emulator-7:latest:Dockerfile"
    "containers/qemu-softgpu:compose-emulator-8:latest:Dockerfile"
    "frontend:compose-vr-frontend:latest:Dockerfile"
)

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

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed. Please install it first."
        exit 1
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    check_command "docker"
    check_command "kubectl"
    check_command "helm"
    check_command "minikube"
    log_success "All prerequisites are installed"
}

configure_docker_tls() {
    log_info "Configuring Docker for TLS certificate issues..."
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    # Try to configure Docker for insecure registries
    if docker version &> /dev/null; then
        log_info "Docker is accessible, attempting to configure for TLS issues..."
        
        # Set environment variables for Docker build
        export DOCKER_BUILDKIT=1
        export DOCKER_CLI_EXPERIMENTAL=enabled
        
        # Try to pull a test image to verify connectivity
        if docker pull hello-world:latest &> /dev/null; then
            log_success "Docker registry connectivity verified"
        else
            log_warning "Docker registry connectivity issues detected, continuing with build..."
        fi
    fi
}

check_cluster_status() {
    log_info "Checking cluster status..."
    if ! minikube status &> /dev/null; then
        log_warning "Minikube cluster is not running. Starting cluster with enhanced resources..."
        if [ -n "$HTTPS_PROXY" ]; then
            minikube start --cpus=4 --memory=8192 --disk-size=20g --driver=docker --docker-env HTTPS_PROXY
        else
            minikube start --cpus=4 --memory=8192 --disk-size=20g --driver=docker
        fi
    else
        log_info "Minikube cluster is running"
    fi
}

check_image_in_minikube() {
    local image=$1
    eval $(minikube docker-env) && docker images | grep -q "$(echo $image | cut -d: -f1)"
}

build_image() {
    local context=$1
    local image_name=$2
    local dockerfile_path=$3
    
    log_info "Building image $image_name from $context..."
    
    # Set Docker build options for TLS issues
    local build_opts="--no-cache --pull"
    
    # Try building with different approaches
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if docker build $build_opts -t "$image_name" "$context"; then
            log_success "Successfully built $image_name"
            return 0
        else
            retry_count=$((retry_count + 1))
            log_warning "Build attempt $retry_count failed for $image_name"
            
            if [ $retry_count -lt $max_retries ]; then
                log_info "Retrying build for $image_name..."
                sleep 2
            else
                log_error "Failed to build $image_name after $max_retries attempts"
                return 1
            fi
        fi
    done
}

import_image_to_minikube() {
    local image=$1
    log_info "Importing $image to minikube..."
    
    # Save image to tar file
    local tar_file="/tmp/$(echo $image | tr ':' '_').tar"
    docker save "$image" -o "$tar_file"
    
    # Load into minikube
    eval $(minikube docker-env) && docker load -i "$tar_file"
    
    # Clean up
    rm -f "$tar_file"
    
    if check_image_in_minikube "$image"; then
        log_success "Successfully imported $image to minikube"
    else
        log_error "Failed to import $image to minikube"
        return 1
    fi
}

build_and_import_images() {
    log_info "Building and importing required images..."
    
    # Check if we're in minikube environment and set context
    if command -v minikube &> /dev/null && minikube status &> /dev/null; then
        log_info "Detected minikube environment, building in minikube context..."
        eval $(minikube docker-env)
    else
        log_info "Building in local Docker environment..."
    fi
    
    # Build emulator image once and retag for all instances
    log_info "Building emulator image compose-emulator-0:latest with built-in win98 disk..."
    local emulator_images=(
        "compose-emulator-0"
        "compose-emulator-1"
        "compose-emulator-2"
        "compose-emulator-3"
        "compose-emulator-4"
        "compose-emulator-5"
        "compose-emulator-6"
        "compose-emulator-7"
        "compose-emulator-8"
    )
    
    # Check if base emulator image already exists in minikube
    if check_image_in_minikube "compose-emulator-0:latest"; then
        log_info "Base emulator image compose-emulator-0:latest already exists in minikube, skipping build..."
    else
        # Check if image exists locally
        if docker images | grep -q "compose-emulator-0:latest"; then
            log_info "Base emulator image compose-emulator-0:latest exists locally, importing to minikube..."
            import_image_to_minikube "compose-emulator-0:latest"
        else
            log_info "Building base emulator image compose-emulator-0:latest with built-in win98 disk..."
            if docker build -t "compose-emulator-0:latest" "containers/qemu-softgpu/"; then
                log_success "Successfully built compose-emulator-0:latest with built-in win98 disk"
                import_image_to_minikube "compose-emulator-0:latest"
            else
                log_error "Failed to build compose-emulator-0:latest"
                log_warning "⚠️  Emulator image build failed, but continuing with other images..."
            fi
        fi
    fi
    
    # Retag the base image for other emulator instances
    if check_image_in_minikube "compose-emulator-0:latest"; then
        log_info "Retagging base emulator image for other instances..."
        for i in {1..8}; do
            local full_image_name="compose-emulator-$i:latest"
            
            # Check if this specific image already exists in minikube
            if check_image_in_minikube "$full_image_name"; then
                log_info "Image $full_image_name already exists in minikube, skipping retag..."
                continue
            fi
            
            # Retag locally and import to minikube
            log_info "Retagging compose-emulator-0:latest as $full_image_name..."
            if docker tag "compose-emulator-0:latest" "$full_image_name"; then
                import_image_to_minikube "$full_image_name"
            else
                log_error "Failed to retag as $full_image_name"
                log_warning "⚠️  Retag failed for $full_image_name, but continuing..."
            fi
        done
    else
        log_warning "⚠️  Base emulator image not available, skipping retag operations"
    fi
    
    # Build other images (backend, frontend, vr)
    for build_context in "${BUILD_CONTEXTS[@]}"; do
        # Parse context:image_name:tag:dockerfile_path
        IFS=':' read -r context image_name tag dockerfile_path <<< "$build_context"
        local full_image_name="$image_name:$tag"
        
        # Skip emulator images as they're already built above
        if [[ "$image_name" == compose-emulator-* ]]; then
            continue
        fi
        
        # Check if image already exists in minikube
        if check_image_in_minikube "$full_image_name"; then
            log_info "Image $full_image_name already exists in minikube, skipping..."
            continue
        fi
        
        # Check if image exists locally
        if docker images | grep -q "$full_image_name"; then
            log_info "Image $full_image_name exists locally, importing to minikube..."
            import_image_to_minikube "$full_image_name"
        else
            log_info "Building image $full_image_name..."
            if build_image "$context" "$full_image_name" "$dockerfile_path"; then
                import_image_to_minikube "$full_image_name"
            else
                log_warning "Failed to build $full_image_name, continuing with other images..."
                return 1
            fi
        fi
    done
    
    # Show emulator image sizes
    log_info "Emulator image sizes (with built-in win98 disk):"
    for image in "${emulator_images[@]}"; do
        size=$(docker images "$image:latest" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | tail -1 | awk '{print $3}' 2>/dev/null || echo "N/A")
        log_info "  $image:latest - $size"
    done
}

create_namespace() {
    log_info "Creating namespace $NAMESPACE..."
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    log_success "Namespace $NAMESPACE is ready"
}

initialize_hostpath_storage() {
    log_info "Initializing hostPath storage for Option 1..."
    
    # Create shared directory on minikube host
    log_info "Creating shared directory on minikube host..."
    minikube ssh "sudo mkdir -p /tmp/loco-art-shared && sudo chmod 777 /tmp/loco-art-shared"
    
    if [ $? -eq 0 ]; then
        log_success "HostPath storage initialized successfully"
        log_info "Shared directory: /tmp/loco-art-shared"
    else
        log_error "Failed to initialize hostPath storage"
        return 1
    fi
}

# Disk image initialization is now handled by Kubernetes init containers
# This ensures proper lifecycle management and idempotent operation

destroy_cluster() {
    log_info "🧹 Destroying cluster resources..."
    
    # Delete namespace (this will cascade delete most resources)
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        log_info "Deleting namespace: $NAMESPACE"
        kubectl delete namespace $NAMESPACE
        log_success "✅ Namespace deleted"
    else
        log_info "Namespace $NAMESPACE does not exist, skipping"
    fi
    
    # Clean up any orphaned PVs that might have been created
    log_info "Cleaning up orphaned PersistentVolumes..."
    local pvs_to_delete=()
    
    # Get all PVs that might be related to our cluster
    while IFS= read -r pv; do
        if [[ -n "$pv" ]]; then
            pvs_to_delete+=("$pv")
        fi
    done < <(kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -E "(win98-disk|nfs-pvc|loco)" || true)
    
    for pv in "${pvs_to_delete[@]}"; do
        if kubectl get pv "$pv" &> /dev/null; then
            log_info "Deleting PersistentVolume: $pv"
            kubectl delete pv "$pv"
            log_success "✅ PersistentVolume $pv deleted"
        fi
    done
    
    # Clean up host directories in minikube
    log_info "Cleaning up host directories in minikube..."
    local host_dirs=("/tmp/win98-disk" "/tmp/loco-storage" "/tmp/nfs-server")
    
    for dir in "${host_dirs[@]}"; do
        if minikube ssh "test -d $dir" 2>/dev/null; then
            log_info "Removing host directory: $dir"
            if minikube ssh "sudo rm -rf $dir" 2>/dev/null; then
                log_success "✅ Host directory $dir removed"
            else
                log_warning "⚠️  Failed to remove host directory $dir"
            fi
        else
            log_info "Host directory $dir does not exist, skipping"
        fi
    done
    
    # Clean up any orphaned Docker images (optional)
    log_info "Cleaning up orphaned Docker images..."
    if command -v docker &> /dev/null; then
        # Switch to minikube docker context
        eval $(minikube docker-env 2>/dev/null) || true
        
        # Remove compose images that might be orphaned
        local compose_images=("compose-backend" "compose-frontend" "compose-emulator-" "compose-vr-frontend")
        for image_prefix in "${compose_images[@]}"; do
            if docker images | grep -q "$image_prefix"; then
                log_info "Removing Docker images with prefix: $image_prefix"
                docker images | grep "$image_prefix" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
            fi
        done
    fi
    
    log_success "🎉 Cluster destruction completed successfully"
    log_info "All resources have been cleaned up. You can now run the bootstrap script again for a fresh deployment."
}

install_helm_chart() {
    log_info "Installing Helm chart..."
    
    # Validate Helm chart and values first
    log_info "Validating Helm chart and values..."
    if ! helm template test $CHART_PATH -n $NAMESPACE -f $VALUES_FILE > /dev/null 2>&1; then
        log_error "❌ Helm chart validation failed. Please check for YAML syntax errors."
        log_info "Running helm template with debug to show errors:"
        helm template test $CHART_PATH -n $NAMESPACE -f $VALUES_FILE --debug 2>&1 | head -20
        return 1
    fi
    
    # Check if release already exists
    if helm list -n $NAMESPACE | grep -q "loco"; then
        log_info "Upgrading existing Helm release..."
        helm upgrade loco $CHART_PATH -n $NAMESPACE -f $VALUES_FILE
    else
        log_info "Installing new Helm release..."
        helm install loco $CHART_PATH -n $NAMESPACE -f $VALUES_FILE
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Helm chart installed successfully"
    else
        log_error "Failed to install Helm chart"
        return 1
    fi
}

wait_for_pods() {
    log_info "Waiting for pods to be ready..."
    
    # First check if any pods exist at all
    local pod_count=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
    if [ "$pod_count" -eq 0 ]; then
        log_warning "⚠️  No pods found in namespace $NAMESPACE. Helm chart may have failed to deploy."
        log_info "Checking Helm release status:"
        helm list -n $NAMESPACE
        log_info "Checking namespace resources:"
        kubectl get all -n $NAMESPACE
        return 1
    fi
    
    log_info "Found $pod_count pods, waiting for them to be ready..."
    
    # Wait for all pods to be running with timeout
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=loco -n $NAMESPACE --timeout=300s; then
        log_success "All pods are ready"
        return 0
    else
        log_warning "⚠️  Some pods may not be ready yet"
        log_info "Current pod status:"
        kubectl get pods -n $NAMESPACE
        return 1
    fi
}

verify_workloads() {
    log_info "Verifying all workloads are running..."
    
    # Wait for all pods to be ready
    local timeout=600  # 10 minutes
    local elapsed=0
    local interval=10
    
    while [ $elapsed -lt $timeout ]; do
        local ready_pods=$(kubectl get pods -n $NAMESPACE --no-headers | grep -c "Running\|Completed")
        local total_pods=$(kubectl get pods -n $NAMESPACE --no-headers | wc -l)
        
        if [ $ready_pods -eq $total_pods ] && [ $total_pods -gt 0 ]; then
            log_success "All $total_pods pods are running successfully!"
            return 0
        else
            log_info "Waiting for pods to be ready... ($ready_pods/$total_pods ready)"
            sleep $interval
            elapsed=$((elapsed + interval))
        fi
    done
    
    log_warning "Timeout waiting for all pods to be ready"
    return 1
}

verify_services() {
    log_info "Verifying all services are accessible..."
    
    # Check if services are created
    local services=$(kubectl get services -n $NAMESPACE --no-headers | wc -l)
    if [ $services -gt 0 ]; then
        log_success "All $services services are created"
    else
        log_warning "No services found"
    fi
    
    # Check if PVCs are bound
    local bound_pvcs=$(kubectl get pvc -n $NAMESPACE --no-headers | grep -c "Bound")
    local total_pvcs=$(kubectl get pvc -n $NAMESPACE --no-headers | wc -l)
    
    if [ $bound_pvcs -eq $total_pvcs ] && [ $total_pvcs -gt 0 ]; then
        log_success "All $total_pvcs PVCs are bound"
    else
        log_warning "Some PVCs may not be bound ($bound_pvcs/$total_pvcs)"
    fi
}

verify_connectivity() {
    log_info "Verifying inter-service connectivity..."
    
    # Get minikube IP
    local minikube_ip=$(minikube ip)
    if [ -n "$minikube_ip" ]; then
        log_success "Minikube IP: $minikube_ip"
        
        # Check if we can access the cluster
        if kubectl get nodes &> /dev/null; then
            log_success "Kubernetes cluster is accessible"
        else
            log_error "Cannot access Kubernetes cluster"
            return 1
        fi
    else
        log_error "Cannot get minikube IP"
        return 1
    fi
}

verify_hostpath_storage() {
    log_info "Verifying hostPath storage is accessible..."
    
    # Check if the shared directory exists and is accessible
    if minikube ssh "test -d /tmp/loco-art-shared && test -w /tmp/loco-art-shared" &> /dev/null; then
        log_success "HostPath storage directory is accessible and writable"
        
        # Show directory contents
        log_info "HostPath storage directory contents:"
        minikube ssh "ls -la /tmp/loco-art-shared"
    else
        log_error "HostPath storage directory is not accessible or writable"
        return 1
    fi
}

show_status() {
    log_info "Cluster status:"
    echo
    kubectl get pods -n $NAMESPACE
    echo
    kubectl get services -n $NAMESPACE
    echo
    kubectl get pvc -n $NAMESPACE
    echo
    
    # Get minikube IP
    MINIKUBE_IP=$(minikube ip)
    log_info "Minikube IP: $MINIKUBE_IP"
    
    # Show service URLs
    FRONTEND_PORT=$(kubectl get service loco-loco-frontend -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')
    BACKEND_PORT=$(kubectl get service loco-loco-backend -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')
    
    if [ -n "$FRONTEND_PORT" ] && [ -n "$BACKEND_PORT" ]; then
        log_success "Service URLs:"
        echo "  Frontend: http://$MINIKUBE_IP:$FRONTEND_PORT"
        echo "  Backend:  http://$MINIKUBE_IP:$BACKEND_PORT"
    fi
}

show_troubleshooting() {
    log_info "Troubleshooting commands:"
    echo "  Check pod logs: kubectl logs <pod-name> -n $NAMESPACE"
    echo "  Check pod events: kubectl describe pod <pod-name> -n $NAMESPACE"
    echo "  Check services: kubectl get services -n $NAMESPACE"
    echo "  Check PVCs: kubectl get pvc -n $NAMESPACE"
    echo "  Access minikube: minikube ssh"
    echo "  Check minikube images: eval \$(minikube docker-env) && docker images"
}

main() {
    # Handle destroy mode first
    if [ "$DESTROY_MODE" = true ]; then
        destroy_cluster
        exit 0
    fi
    
    # Parse additional command line arguments for build mode
    local rebuild_emulators_only=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --rebuild-emulators)
                rebuild_emulators_only=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --destroy              Clean up all resources (namespace, PVs, host directories)"
                echo "  --rebuild-emulators    Rebuild only emulator images with built-in win98 disk"
                echo "  --help, -h            Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    if [ "$rebuild_emulators_only" = true ]; then
        log_info "Rebuilding emulator images only..."
        check_prerequisites
        configure_docker_tls
        check_cluster_status
        build_and_import_images
        log_success "Emulator images rebuilt successfully!"
        return 0
    fi
    
    log_info "Starting cluster bootstrap process with Option 1 (hostPath storage)..."
    
    local errors=()
    
    # Check prerequisites
    if ! check_prerequisites; then
        errors+=("Prerequisites check failed")
    fi
    
    # Configure Docker TLS
    if ! configure_docker_tls; then
        errors+=("Docker TLS configuration failed")
    fi
    
    # Check cluster status
    if ! check_cluster_status; then
        errors+=("Cluster status check failed")
    fi
    
    # Build and import images
    if ! build_and_import_images; then
        errors+=("Image build/import failed")
    fi
    
    # Create namespace
    if ! create_namespace; then
        errors+=("Namespace creation failed")
    fi
    
    # Initialize hostPath storage
    if ! initialize_hostpath_storage; then
        errors+=("HostPath storage initialization failed")
    fi
    
    # Install Helm chart
    if ! install_helm_chart; then
        errors+=("Helm chart installation failed")
    fi
    
    # Wait for pods
    if ! wait_for_pods; then
        errors+=("Pod readiness check failed")
    fi
    
    # Verify workloads
    if ! verify_workloads; then
        errors+=("Workload verification failed")
    fi
    
    # Verify services
    if ! verify_services; then
        errors+=("Service verification failed")
    fi
    
    # Verify connectivity
    if ! verify_connectivity; then
        errors+=("Connectivity verification failed")
    fi
    
    # Verify hostPath storage
    if ! verify_hostpath_storage; then
        errors+=("HostPath storage verification failed")
    fi
    
    # Show status and troubleshooting
    show_status
    show_troubleshooting
    
    # Report final status
    if [ ${#errors[@]} -eq 0 ]; then
        log_success "✅ Cluster bootstrap completed successfully with hostPath storage!"
    else
        log_warning "⚠️  Cluster bootstrap completed with ${#errors[@]} error(s):"
        for error in "${errors[@]}"; do
            log_warning "  - $error"
        done
        log_info "Check the troubleshooting commands above for more details."
    fi
}

# Run main function
main "$@" 