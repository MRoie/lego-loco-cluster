#!/bin/bash

# Lego Loco Cluster - Docker Compose Management Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $1"
}

show_help() {
    cat << EOF
Lego Loco Cluster - Docker Compose Management

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    up [dev|prod]     Start the cluster (default: dev)
    down              Stop and remove all containers
    build             Build all container images
    logs [service]    Show logs for service (or all services)
    status            Show status of all services
    restart [service] Restart service (or all services)
    setup             Setup prerequisites and TAP bridge
    clean             Clean up everything (containers, images, volumes)
    cleanup-ports     Clean up ports and stop conflicting containers

Options:
    --full            Start all 9 emulators (dev mode default: 3)
    --no-build        Don't build images before starting
    --no-cleanup      Skip port cleanup before starting
    --pull            Pull latest images before starting

Examples:
    $0 up dev         # Start development environment (3 emulators)
    $0 up dev --full  # Start development environment (9 emulators)
    $0 up prod        # Start production environment
    $0 logs backend   # Show backend logs
    $0 restart emulator-0  # Restart first emulator

EOF
}

setup_prerequisites() {
    print_status "Setting up prerequisites..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check if user can access Docker
    if ! docker ps >/dev/null 2>&1; then
        print_warning "Cannot access Docker. You may need to add your user to the docker group:"
        echo "  sudo usermod -aG docker \$USER"
        echo "  newgrp docker"
    fi
    
    # Setup TAP bridge if it doesn't exist
    if ! ip link show loco-br >/dev/null 2>&1; then
        print_status "Setting up TAP bridge..."
        if [[ -f scripts/setup_bridge.sh ]]; then
            sudo ./scripts/setup_bridge.sh
        else
            print_warning "TAP bridge setup script not found. Emulators may have networking issues."
        fi
    else
        print_success "TAP bridge already exists"
    fi
    
    # Create necessary directories
    mkdir -p images config
    
    # Check if Windows 98 image exists
    if [[ ! -f images/win98.qcow2 ]]; then
        print_warning "Windows 98 image not found at images/win98.qcow2"
        print_status "You can download it using: ./scripts/download_and_run_qemu.sh"
    fi
    
    print_success "Prerequisites setup complete"
}

build_images() {
    print_status "Building container images..."
    
    if docker-compose build; then
        print_success "All images built successfully"
    else
        print_error "Image build failed"
        exit 1
    fi
}

start_cluster() {
    local env=${1:-dev}
    local compose_files="-f docker-compose.yml"
    local additional_args=""
    
    case $env in
        dev)
            compose_files+=" -f docker-compose.override.yml"
            if [[ "$*" == *"--full"* ]]; then
                additional_args="--profile full"
            fi
            ;;
        prod)
            compose_files+=" -f docker-compose.prod.yml"
            ;;
        *)
            print_error "Invalid environment: $env. Use 'dev' or 'prod'"
            exit 1
            ;;
    esac
    
    # Clean up ports and containers before starting
    if [[ "$*" != *"--no-cleanup"* ]]; then
        cleanup_ports
    fi
    
    if [[ "$*" != *"--no-build"* ]]; then
        print_status "Building images..."
        docker-compose $compose_files build
    fi
    
    if [[ "$*" == *"--pull"* ]]; then
        print_status "Pulling latest images..."
        docker-compose $compose_files pull
    fi
    
    print_status "Starting Lego Loco Cluster ($env environment)..."
    
    if docker-compose $compose_files up -d $additional_args; then
        print_success "Cluster started successfully"
        
        # Wait for services to be ready
        print_status "Waiting for services to be ready..."
        sleep 10
        
        # Check service health
        print_status "Service status:"
        docker-compose $compose_files ps
        
        echo ""
        print_success "🎉 Lego Loco Cluster is ready!"
        echo ""
        echo -e "${BLUE}📋 Service URLs:${NC}"
        echo "  Frontend:     http://localhost:3000"
        echo "  Backend:      http://localhost:3001"
        echo "  Registry:     http://localhost:5500"
        echo ""
        echo -e "${BLUE}🖥️  VNC Access:${NC}"
        echo "  Emulator 0:   vnc://localhost:5901"
        echo "  Emulator 1:   vnc://localhost:5902"
        echo "  Emulator 2:   vnc://localhost:5903"
        if [[ "$env" == "prod" ]] || [[ "$*" == *"--full"* ]]; then
            echo "  Emulator 3-8: vnc://localhost:5904-5909"
        fi
        echo ""
        echo -e "${BLUE}🌐 Web VNC:${NC}"
        echo "  Emulator 0:   http://localhost:6080"
        echo "  Emulator 1:   http://localhost:6081"
        echo "  Emulator 2:   http://localhost:6082"
        if [[ "$env" == "prod" ]] || [[ "$*" == *"--full"* ]]; then
            echo "  Emulator 3-8: http://localhost:6083-6088"
        fi
        echo ""
        echo -e "${YELLOW}💡 Useful Commands:${NC}"
        echo "  Check logs:   $0 logs [service]"
        echo "  Stop cluster: $0 down"
        echo "  Restart:      $0 restart [service]"
        
    else
        print_error "Failed to start cluster"
        exit 1
    fi
}

cleanup_ports() {
    print_status "Cleaning up ports and containers..."
    
    # List of ports used by the lego-loco cluster
    local ports=(3000 3001 5500 5901 5902 5903 5904 5905 5906 5907 5908 5909 6080 6081 6082 6083 6084 6085 6086 6087 6088 7000 7001 7002 7003 7004 7005 7006 7007 7008)
    
    # Stop all Docker Compose setups first
    print_status "Stopping all Docker Compose setups..."
    docker-compose -f docker-compose.yml -f docker-compose.override.yml down --remove-orphans 2>/dev/null || true
    docker-compose -f docker-compose.yml -f docker-compose.prod.yml down --remove-orphans 2>/dev/null || true
    docker-compose -f docker-compose.minimal.yml down --remove-orphans 2>/dev/null || true
    docker-compose down --remove-orphans 2>/dev/null || true
    
    # Stop all loco containers (including any orphaned ones)
    print_status "Stopping all loco containers..."
    docker ps -q --filter "name=loco" | xargs -r docker stop 2>/dev/null || true
    docker ps -aq --filter "name=loco" | xargs -r docker rm -f 2>/dev/null || true
    
    # Also stop containers that might be using our ports
    for port in "${ports[@]}"; do
        local containers=$(docker ps --format "table {{.ID}}\t{{.Ports}}" | grep ":$port->" | awk '{print $1}' | tail -n +2 2>/dev/null || true)
        if [[ -n "$containers" ]]; then
            print_status "Stopping containers using port $port: $containers"
            echo "$containers" | xargs -r docker stop 2>/dev/null || true
            echo "$containers" | xargs -r docker rm -f 2>/dev/null || true
        fi
    done
    
    # Kill processes using our ports
    for port in "${ports[@]}"; do
        local pids=$(lsof -ti tcp:$port 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            print_status "Killing processes using port $port: $pids"
            echo "$pids" | xargs -r kill -9 2>/dev/null || true
        fi
    done
    
    # Wait a moment for cleanup to complete
    sleep 2
    
    print_success "Port cleanup complete"
}

stop_cluster() {
    print_status "Stopping Lego Loco Cluster..."
    
    # Cleanup ports and containers first
    cleanup_ports
    
    # Stop with all possible compose files
    docker-compose -f docker-compose.yml -f docker-compose.override.yml -f docker-compose.prod.yml down 2>/dev/null || true
    
    print_success "Cluster stopped"
}

show_logs() {
    local service=$1
    local compose_files="-f docker-compose.yml -f docker-compose.override.yml"
    
    if [[ -n "$service" ]]; then
        docker-compose $compose_files logs -f "$service"
    else
        docker-compose $compose_files logs -f
    fi
}

show_status() {
    print_status "Lego Loco Cluster Status:"
    echo ""
    
    # Show running containers
    docker-compose -f docker-compose.yml ps
    
    echo ""
    print_status "Resource Usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
}

restart_service() {
    local service=$1
    local compose_files="-f docker-compose.yml -f docker-compose.override.yml"
    
    if [[ -n "$service" ]]; then
        print_status "Restarting $service..."
        docker-compose $compose_files restart "$service"
        print_success "$service restarted"
    else
        print_status "Restarting all services..."
        docker-compose $compose_files restart
        print_success "All services restarted"
    fi
}

clean_everything() {
    print_warning "This will remove all containers, images, and volumes. Are you sure? [y/N]"
    read -r response
    if [[ "$response" == "y" || "$response" == "Y" ]]; then
        print_status "Cleaning up everything..."
        
        # Stop everything
        docker-compose -f docker-compose.yml -f docker-compose.override.yml -f docker-compose.prod.yml down -v --rmi all
        
        # Remove any remaining loco containers
        docker ps -a --filter name=loco --format "{{.ID}}" | xargs -r docker rm -f
        
        # Remove any remaining loco images
        docker images --filter reference="*loco*" --format "{{.ID}}" | xargs -r docker rmi -f
        
        print_success "Cleanup complete"
    else
        print_status "Cleanup cancelled"
    fi
}

# Main script logic
case "${1:-}" in
    up)
        setup_prerequisites
        start_cluster "${2:-dev}" "${@:2}"
        ;;
    down)
        stop_cluster
        ;;
    build)
        build_images
        ;;
    logs)
        show_logs "${2:-}"
        ;;
    status)
        show_status
        ;;
    restart)
        restart_service "${2:-}"
        ;;
    setup)
        setup_prerequisites
        ;;
    cleanup-ports)
        cleanup_ports
        ;;
    clean)
        clean_everything
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
