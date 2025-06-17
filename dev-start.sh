#!/bin/bash

# Development startup script for Lego Loco Cluster
# Provides live monitoring with Docker containers and volume mounting

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

print_dev() {
    echo -e "${PURPLE}[$(date '+%H:%M:%S')] 🚀${NC} $1"
}

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]]; then
    print_error "docker-compose.yml not found. Run this script from the project root."
    exit 1
fi

print_dev "🐳 Starting Lego Loco Cluster Development Environment"

# Function to cleanup
cleanup() {
    print_status "Shutting down development environment..."
    docker-compose -f docker-compose.yml -f docker-compose.dev.yml down
    print_status "Development environment stopped"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Parse command line arguments
DEV_MODE="full"
FORCE_REBUILD=false
SHOW_LOGS=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --minimal)
            DEV_MODE="minimal"
            shift
            ;;
        --rebuild)
            FORCE_REBUILD=true
            shift
            ;;
        --no-logs)
            SHOW_LOGS=false
            shift
            ;;
        --help|-h)
            cat << EOF
Development Environment for Lego Loco Cluster

Usage: $0 [OPTIONS]

Options:
    --minimal     Start minimal services only (backend + frontend)
    --rebuild     Force rebuild of Docker images
    --no-logs     Don't follow logs after startup
    --help        Show this help message

Features:
    🔄 Live reloading for backend (nodemon)
    🔄 Live reloading for frontend (Vite dev server)
    📁 Volume mounting for instant code changes
    🐛 Debug port exposed (9229) for backend
    🌐 Hot module replacement for frontend

URLs:
    Frontend: http://localhost:3000
    Backend:  http://localhost:3001
    Debug:    chrome://inspect (connect to localhost:9229)

Press Ctrl+C to stop the development environment.
EOF
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Stop any existing containers
print_status "Stopping any existing containers..."
docker-compose -f docker-compose.yml -f docker-compose.dev.yml down 2>/dev/null || true

# Build images if needed
if [[ "$FORCE_REBUILD" == "true" ]]; then
    print_status "Force rebuilding Docker images..."
    docker-compose -f docker-compose.yml -f docker-compose.dev.yml build --no-cache
else
    print_status "Building Docker images..."
    docker-compose -f docker-compose.yml -f docker-compose.dev.yml build
fi

# Start services based on mode
if [[ "$DEV_MODE" == "minimal" ]]; then
    print_dev "Starting minimal development services (backend + frontend)..."
    docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d backend frontend
else
    print_dev "Starting full development environment..."
    docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d
fi

# Wait for services to be ready
print_status "Waiting for services to start..."
sleep 5

# Check service health
print_status "Checking service health..."

# Check backend
for i in {1..10}; do
    if curl -s -f http://localhost:3001/health >/dev/null 2>&1; then
        print_success "Backend is ready at http://localhost:3001"
        break
    else
        if [[ $i -eq 10 ]]; then
            print_warning "Backend health check failed after 10 attempts"
        else
            print_status "Waiting for backend... (attempt $i/10)"
            sleep 2
        fi
    fi
done

# Check frontend
for i in {1..10}; do
    if curl -s -f http://localhost:3000 >/dev/null 2>&1; then
        print_success "Frontend is ready at http://localhost:3000"
        break
    else
        if [[ $i -eq 10 ]]; then
            print_warning "Frontend health check failed after 10 attempts"
        else
            print_status "Waiting for frontend... (attempt $i/10)"
            sleep 2
        fi
    fi
done

# Show running containers
print_status "Running containers:"
docker-compose -f docker-compose.yml -f docker-compose.dev.yml ps

echo ""
print_success "🎉 Development Environment Ready!"
echo ""
echo -e "${BLUE}📋 Development URLs:${NC}"
echo "  Frontend (Vite):  http://localhost:3000"
echo "  Backend (Express): http://localhost:3001"
echo "  Backend Debug:     chrome://inspect (connect to localhost:9229)"
echo ""
echo -e "${BLUE}🔧 Development Features:${NC}"
echo "  ✅ Live backend reloading (nodemon)"
echo "  ✅ Live frontend reloading (Vite HMR)"
echo "  ✅ Volume mounting for instant changes"
echo "  ✅ Debug port exposed for backend"
echo "  ✅ Source maps enabled"
echo ""
echo -e "${BLUE}📁 Monitored Directories:${NC}"
echo "  Backend:  ./backend/ (mounted to /app)"
echo "  Frontend: ./frontend/ (mounted to /app)"
echo "  Config:   ./config/ (mounted to /app/config)"
echo ""
echo -e "${YELLOW}💡 Development Tips:${NC}"
echo "  • Edit files in ./backend/ or ./frontend/ for instant reloading"
echo "  • Check container logs: docker-compose logs -f <service>"
echo "  • Rebuild after package.json changes: $0 --rebuild"
echo "  • Use Chrome DevTools for backend debugging"
echo ""

if [[ "$SHOW_LOGS" == "true" ]]; then
    print_dev "Following container logs (press Ctrl+C to stop)..."
    echo ""
    docker-compose -f docker-compose.yml -f docker-compose.dev.yml logs -f
else
    print_dev "Development environment running. Press Ctrl+C to stop."
    
    # Keep script running until interrupted
    while true; do
        sleep 1
    done
fi
