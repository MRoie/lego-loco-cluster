#!/usr/bin/env bash
# scripts/start_docker_daemon.sh - Reliable Docker daemon startup for CI environments
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/docker-daemon.log"

echo "Starting Docker daemon for CI environment" | tee -a "$LOG_FILE"

# Check if Docker daemon is already running
if pgrep dockerd >/dev/null 2>&1; then
    echo "Docker daemon is already running" | tee -a "$LOG_FILE"
    docker version | tee -a "$LOG_FILE"
    exit 0
fi

# Start Docker daemon with better logging and error handling
echo "Starting dockerd..." | tee -a "$LOG_FILE"
dockerd >> "$LOG_FILE" 2>&1 &
DOCKERD_PID=$!
echo "Started dockerd with PID: $DOCKERD_PID" | tee -a "$LOG_FILE"

# Wait for Docker to be fully ready with extended timeout
echo "Waiting for Docker daemon to be ready..." | tee -a "$LOG_FILE"
timeout=60
ready=false

while [ $timeout -gt 0 ]; do
    if docker info >/dev/null 2>&1; then
        ready=true
        break
    fi
    ((timeout--))
    sleep 1
done

if [ "$ready" = false ]; then
    echo "❌ Docker daemon failed to start within 60 seconds" | tee -a "$LOG_FILE"
    echo "Docker daemon logs:" | tee -a "$LOG_FILE"
    tail -20 "$LOG_FILE" 2>/dev/null || true
    echo "Process list:" | tee -a "$LOG_FILE"
    ps aux | grep docker | tee -a "$LOG_FILE" || true
    exit 1
fi

echo "✅ Docker daemon ready" | tee -a "$LOG_FILE"
docker version | tee -a "$LOG_FILE"
echo "Docker daemon started successfully" | tee -a "$LOG_FILE"