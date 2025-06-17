#!/bin/bash

# Health check script for Lego Loco Docker Compose services

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

check_service_health() {
    local service=$1
    local url=$2
    local expected_code=${3:-200}
    
    print_status "Checking $service health..."
    
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "$expected_code"; then
        print_success "$service is healthy"
        return 0
    else
        print_error "$service health check failed"
        return 1
    fi
}

check_vnc_connection() {
    local instance=$1
    local port=$2
    
    print_status "Checking VNC connection for $instance..."
    
    if timeout 5 bash -c "</dev/tcp/localhost/$port"; then
        print_success "$instance VNC is accessible"
        return 0
    else
        print_error "$instance VNC connection failed"
        return 1
    fi
}

check_container_status() {
    local container=$1
    
    if docker ps --filter "name=$container" --filter "status=running" | grep -q "$container"; then
        print_success "$container is running"
        return 0
    else
        print_error "$container is not running"
        return 1
    fi
}

main() {
    echo "🏥 Lego Loco Cluster Health Check"
    echo "================================="
    echo ""
    
    local failed=0
    
    # Check if Docker Compose is running
    print_status "Checking Docker Compose services..."
    if docker-compose ps | grep -q "Up"; then
        print_success "Docker Compose services are running"
    else
        print_error "No Docker Compose services found"
        exit 1
    fi
    
    echo ""
    
    # Check core services
    print_status "Checking core services..."
    
    # Registry
    if check_service_health "Registry" "http://localhost:5000/v2/" "200\|404"; then
        :
    else
        ((failed++))
    fi
    
    # Backend
    if check_service_health "Backend" "http://localhost:3001/health" "200"; then
        :
    else
        ((failed++))
    fi
    
    # Frontend
    if check_service_health "Frontend" "http://localhost:3000" "200"; then
        :
    else
        ((failed++))
    fi
    
    echo ""
    
    # Check emulator services
    print_status "Checking emulator services..."
    
    # Get list of running emulator containers
    local emulators=($(docker ps --filter "name=loco-emulator" --format "{{.Names}}" | sort))
    
    if [[ ${#emulators[@]} -eq 0 ]]; then
        print_warning "No emulator containers found"
    else
        print_status "Found ${#emulators[@]} emulator(s)"
        
        for emulator in "${emulators[@]}"; do
            # Extract instance number
            local instance_num=$(echo "$emulator" | grep -o '[0-9]\+' | tail -1)
            local vnc_port=$((5901 + ${instance_num:-0}))
            
            if check_container_status "$emulator"; then
                # Check VNC port
                if check_vnc_connection "$emulator" "$vnc_port"; then
                    :
                else
                    ((failed++))
                fi
            else
                ((failed++))
            fi
        done
    fi
    
    echo ""
    
    # Check networking
    print_status "Checking networking..."
    
    # Check TAP bridge
    if ip link show loco-br >/dev/null 2>&1; then
        print_success "TAP bridge (loco-br) exists"
    else
        print_warning "TAP bridge (loco-br) not found"
        ((failed++))
    fi
    
    # Check Docker network
    if docker network inspect lego-loco-cluster_loco-network >/dev/null 2>&1; then
        print_success "Docker network exists"
    else
        print_warning "Docker network not found"
        ((failed++))
    fi
    
    echo ""
    
    # Resource usage
    print_status "Resource usage summary..."
    echo ""
    
    # Memory usage
    local total_memory=$(docker stats --no-stream --format "{{.MemUsage}}" | grep -o '[0-9.]*GiB\|[0-9.]*MiB' | awk '{sum += $1} END {print sum "MiB"}')
    echo "💾 Total memory usage: $total_memory"
    
    # Container count
    local container_count=$(docker ps --filter "name=loco" --format "{{.Names}}" | wc -l)
    echo "📦 Running containers: $container_count"
    
    # Network ports
    echo "🌐 Exposed ports:"
    docker ps --filter "name=loco" --format "table {{.Names}}\t{{.Ports}}" | grep -E "(frontend|backend|emulator)" | while read -r line; do
        echo "  $line"
    done
    
    echo ""
    
    # Summary
    if [[ $failed -eq 0 ]]; then
        print_success "🎉 All health checks passed!"
        echo ""
        echo "✅ Ready to use:"
        echo "  Frontend: http://localhost:3000"
        echo "  Backend:  http://localhost:3001"
        echo "  VNC:      vnc://localhost:5901 (first emulator)"
        exit 0
    else
        print_error "❌ $failed health check(s) failed"
        echo ""
        echo "💡 Troubleshooting:"
        echo "  Check logs:    ./docker-compose.sh logs [service]"
        echo "  Restart:       ./docker-compose.sh restart [service]"
        echo "  Full restart:  ./docker-compose.sh down && ./docker-compose.sh up dev"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Health check for Lego Loco Docker Compose services"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --quiet, -q   Minimal output"
        echo "  --verbose, -v Verbose output"
        exit 0
        ;;
    --quiet|-q)
        # Redirect output to only show errors
        exec 1>/dev/null
        ;;
    --verbose|-v)
        # Enable debug output
        set -x
        ;;
esac

main "$@"
