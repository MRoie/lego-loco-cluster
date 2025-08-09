#!/usr/bin/env bash
# Start port-forwarding to services in the live kind cluster with comprehensive logging
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LIVE_LOG="$LOG_DIR/live-cluster-start.log"

exec > >(tee -a "$LIVE_LOG") 2>&1

echo "=== STARTING LIVE CLUSTER PORT FORWARDS ===" && date

BACKEND_SERVICE="loco-loco-backend"
FRONTEND_SERVICE="loco-loco-frontend"
VR_SERVICE="loco-loco-vr"
EMULATOR_STATEFULSET="loco-loco-emulator"

# Enhanced service verification
echo "Verifying services exist..."
if ! kubectl get svc "$BACKEND_SERVICE" >/dev/null 2>&1; then
    echo "❌ Backend service $BACKEND_SERVICE not found"
    kubectl get svc -A | grep -E "(backend|loco)" || echo "No backend services found"
    exit 1
fi

if ! kubectl get svc "$FRONTEND_SERVICE" >/dev/null 2>&1; then
    echo "❌ Frontend service $FRONTEND_SERVICE not found"
    kubectl get svc -A | grep -E "(frontend|loco)" || echo "No frontend services found"
    exit 1
fi

if ! kubectl get svc "$VR_SERVICE" >/dev/null 2>&1; then
    echo "❌ VR service $VR_SERVICE not found"
    kubectl get svc -A | grep -E "(vr|loco)" || echo "No VR services found"
    exit 1
fi

echo "✅ All required services found"

# Show detailed cluster state before starting port forwards
echo "=== CLUSTER STATE BEFORE PORT FORWARDS ==="
kubectl get pods -A
kubectl get svc -A
kubectl get statefulset -A

# Start port-forward for backend with enhanced logging
echo "Starting backend port-forward..."
kubectl port-forward svc/$BACKEND_SERVICE 3001:3001 > "$LOG_DIR/pf_backend.log" 2>&1 &
BACKEND_PID=$!
PIDS=("$BACKEND_PID")
echo "Backend port-forward started (PID: $BACKEND_PID)"

echo "Starting frontend port-forward..."
kubectl port-forward svc/$FRONTEND_SERVICE 3000:3000 > "$LOG_DIR/pf_frontend.log" 2>&1 &
FRONTEND_PID=$!
PIDS+=("$FRONTEND_PID")
echo "Frontend port-forward started (PID: $FRONTEND_PID)"

echo "Starting VR port-forward..."
kubectl port-forward svc/$VR_SERVICE 3002:3000 > "$LOG_DIR/pf_vr.log" 2>&1 &
VR_PID=$!
PIDS+=("$VR_PID")
echo "VR port-forward started (PID: $VR_PID)"

# Wait for port forwards to establish
echo "Waiting for port forwards to establish..."
sleep 5

# Test connectivity
echo "=== TESTING SERVICE CONNECTIVITY ==="
for service in "backend:3001" "frontend:3000" "vr:3002"; do
    name=$(echo $service | cut -d: -f1)
    port=$(echo $service | cut -d: -f2)
    echo "Testing $name on port $port..."
    if curl -f -s "http://localhost:$port" >/dev/null 2>&1; then
        echo "✅ $name responding on port $port"
    else
        echo "❌ $name not responding on port $port"
    fi
done

# Handle emulator instances
echo "=== SETTING UP EMULATOR PORT FORWARDS ==="
if ! kubectl get statefulset "$EMULATOR_STATEFULSET" >/dev/null 2>&1; then
    echo "⚠️  Emulator StatefulSet $EMULATOR_STATEFULSET not found"
    kubectl get statefulset -A | grep -E "(emulator|loco)" || echo "No emulator statefulsets found"
    REPLICAS=0
else
    REPLICAS=$(kubectl get statefulset "$EMULATOR_STATEFULSET" -o jsonpath='{.spec.replicas}')
    echo "Found StatefulSet with $REPLICAS replicas"
fi

CONFIG=/tmp/live_instances.json
printf '[' > "$CONFIG"

if [ "$REPLICAS" -gt 0 ]; then
    echo "Setting up port forwards for $REPLICAS emulator instances..."
    for ((i=0;i<REPLICAS;i++)); do
        local_port=$((6090+i))
        pod_name="${EMULATOR_STATEFULSET}-${i}"
        
        echo "Setting up port-forward for pod $pod_name on port $local_port..."
        
        # Check if pod exists and is ready
        if kubectl get pod "$pod_name" >/dev/null 2>&1; then
            kubectl port-forward pod/"$pod_name" ${local_port}:6080 \
                > "$LOG_DIR/pf_emulator_${i}.log" 2>&1 &
            EMULATOR_PID=$!
            PIDS+=("$EMULATOR_PID")
            echo "Emulator $i port-forward started (PID: $EMULATOR_PID)"
        else
            echo "⚠️  Pod $pod_name not found or not ready"
            kubectl get pods | grep -E "(emulator|$EMULATOR_STATEFULSET)" || echo "No emulator pods found"
        fi
        
        printf '\n  {"id":"instance-%d","streamUrl":"http://localhost:%d"}' "$i" "$local_port" >> "$CONFIG"
        if [ $i -lt $((REPLICAS-1)) ]; then
            printf ',' >> "$CONFIG"
        fi
    done
else
    echo "⚠️  No emulator replicas to configure"
    # Add a mock instance for testing
    printf '\n  {"id":"mock-instance","streamUrl":"http://localhost:6090"}' >> "$CONFIG"
fi

printf '\n]\n' >> "$CONFIG"

# Save PIDs for cleanup
printf '%s ' "${PIDS[@]}" > /tmp/live_cluster_pids

echo "=== LIVE CLUSTER SETUP COMPLETED ==="
echo "Port-forwards started: ${#PIDS[@]} processes"
echo "Process PIDs: ${PIDS[*]}"
echo "Instance config written to $CONFIG"
echo "Configuration:"
cat "$CONFIG"

echo "=== FINAL CONNECTIVITY TEST ==="
# Wait a bit more for all forwards to establish
sleep 10

# Test all configured instances
for instance in $(cat "$CONFIG" | grep streamUrl | cut -d'"' -f8); do
    echo "Testing instance: $instance"
    if curl -f -s "$instance" >/dev/null 2>&1; then
        echo "✅ Instance responding: $instance"
    else
        echo "❌ Instance not responding: $instance"
    fi
done

echo "Live cluster port-forwards setup completed" && date
