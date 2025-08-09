#!/usr/bin/env bash
# Stop port-forwarding processes with comprehensive logging
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
STOP_LOG="$LOG_DIR/live-cluster-stop.log"

exec > >(tee -a "$STOP_LOG") 2>&1

echo "=== STOPPING LIVE CLUSTER PORT FORWARDS ===" && date

PID_FILE=/tmp/live_cluster_pids

if [ -f "$PID_FILE" ]; then
    echo "Reading PIDs from $PID_FILE"
    PIDS=($(cat "$PID_FILE"))
    echo "Found ${#PIDS[@]} PIDs to terminate: ${PIDS[*]}"
    
    for pid in "${PIDS[@]}"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "Terminating process $pid..."
            kill "$pid" 2>/dev/null || echo "Failed to kill $pid (may already be dead)"
        else
            echo "Process $pid not running"
        fi
    done
    
    # Wait for graceful termination
    echo "Waiting for processes to terminate..."
    sleep 3
    
    # Force kill any remaining processes
    for pid in "${PIDS[@]}"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "Force killing process $pid..."
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    
    # Cleanup PID file
    rm -f "$PID_FILE"
    echo "✅ Port-forward processes terminated"
else
    echo "⚠️  PID file $PID_FILE not found"
fi

# Additional cleanup - kill any remaining kubectl port-forward processes
echo "Cleaning up any remaining kubectl port-forward processes..."
pkill -f "kubectl port-forward" || echo "No remaining kubectl processes found"

# Clean up deployed resources
echo "Cleaning up deployed Kubernetes resources..."
kubectl delete -k kustomize/base >/dev/null 2>&1 || echo "No resources to cleanup"

# Cleanup temporary files
echo "Cleaning up temporary files..."
rm -f /tmp/live_instances.json
rm -f /tmp/pf_*.log

echo "=== LIVE CLUSTER CLEANUP COMPLETED ===" && date
