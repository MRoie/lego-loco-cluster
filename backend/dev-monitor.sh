#!/bin/bash

# Development monitor script for Lego Loco Backend
# Provides live monitoring with automatic restart on file changes

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

print_monitor() {
    echo -e "${PURPLE}[$(date '+%H:%M:%S')] 👁️${NC} $1"
}

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR"
CONFIG_DIR="$SCRIPT_DIR/../config"

# Check if we're in the right directory
if [[ ! -f "$BACKEND_DIR/server.js" ]]; then
    print_error "server.js not found in $BACKEND_DIR"
    exit 1
fi

print_status "🚀 Starting Lego Loco Backend Development Monitor"
print_status "Backend Dir: $BACKEND_DIR"
print_status "Config Dir: $CONFIG_DIR"

# Function to start the server
start_server() {
    print_status "Starting backend server..."
    cd "$BACKEND_DIR"
    
    # Kill any existing backend processes
    pkill -f "node.*server.js" 2>/dev/null || true
    sleep 1
    
    # Start the server in background
    node server.js &
    SERVER_PID=$!
    
    # Wait a moment and check if it's still running
    sleep 2
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_success "Backend server started (PID: $SERVER_PID)"
        return 0
    else
        print_error "Backend server failed to start"
        return 1
    fi
}

# Function to stop the server
stop_server() {
    if [[ -n "$SERVER_PID" ]] && kill -0 $SERVER_PID 2>/dev/null; then
        print_status "Stopping backend server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
        print_success "Backend server stopped"
    fi
}

# Function to restart the server
restart_server() {
    print_monitor "File change detected - restarting server..."
    stop_server
    if start_server; then
        print_success "✨ Server restarted successfully"
    else
        print_error "Failed to restart server"
    fi
}

# Function to test server health
test_server() {
    if curl -s -f http://localhost:3001/health >/dev/null 2>&1; then
        print_success "Health check passed ✅"
        return 0
    else
        print_warning "Health check failed ⚠️"
        return 1
    fi
}

# Cleanup function
cleanup() {
    print_status "Shutting down development monitor..."
    stop_server
    # Kill any background file watchers
    if [[ -n "$WATCHER_PID" ]]; then
        kill $WATCHER_PID 2>/dev/null || true
    fi
    print_status "Development monitor stopped"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Start the initial server
if ! start_server; then
    print_error "Failed to start initial server"
    exit 1
fi

# Test initial health
sleep 3
test_server

print_monitor "🔍 Monitoring files for changes..."
print_monitor "   - Backend files: $BACKEND_DIR/*.js"
print_monitor "   - Config files: $CONFIG_DIR/*.json"
print_monitor "   - Press Ctrl+C to stop"

# File monitoring loop using inotifywait if available, otherwise fallback to polling
if command -v inotifywait >/dev/null 2>&1; then
    print_monitor "Using inotifywait for file monitoring"
    
    # Monitor with inotifywait
    while true; do
        # Monitor backend JS files and config JSON files
        inotifywait -e modify,create,delete,move \
            "$BACKEND_DIR"/*.js \
            "$CONFIG_DIR"/*.json \
            2>/dev/null || true
        
        restart_server
        
        # Brief pause to avoid rapid restarts
        sleep 1
    done &
    WATCHER_PID=$!
    
else
    print_warning "inotifywait not available, using polling method"
    
    # Fallback: polling method
    LAST_CHECK=$(date +%s)
    
    while true; do
        sleep 2
        
        # Check if any monitored files have changed
        CURRENT_TIME=$(date +%s)
        CHANGED_FILES=$(find "$BACKEND_DIR" -name "*.js" -newer <(date -d "@$LAST_CHECK" +%Y%m%d%H%M.%S) 2>/dev/null || true)
        CHANGED_CONFIGS=$(find "$CONFIG_DIR" -name "*.json" -newer <(date -d "@$LAST_CHECK" +%Y%m%d%H%M.%S) 2>/dev/null || true)
        
        if [[ -n "$CHANGED_FILES" || -n "$CHANGED_CONFIGS" ]]; then
            if [[ -n "$CHANGED_FILES" ]]; then
                print_monitor "Changed backend files: $CHANGED_FILES"
            fi
            if [[ -n "$CHANGED_CONFIGS" ]]; then
                print_monitor "Changed config files: $CHANGED_CONFIGS"
            fi
            restart_server
        fi
        
        # Update last check time
        LAST_CHECK=$CURRENT_TIME
        
        # Periodic health check
        if ((CURRENT_TIME % 30 == 0)); then
            test_server
        fi
    done &
    WATCHER_PID=$!
fi

# Keep the main script running
wait $WATCHER_PID
