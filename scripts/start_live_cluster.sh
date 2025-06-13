#!/usr/bin/env bash
# Start port-forwarding to services in the live kind cluster
set -euo pipefail
BACKEND_SERVICE="loco-loco-backend"
EMULATOR_STATEFULSET="loco-loco-emulator"

# Wait for backend service
kubectl get svc "$BACKEND_SERVICE" >/dev/null

# Start port-forward for backend
kubectl port-forward svc/$BACKEND_SERVICE 3001:3001 >/tmp/pf_backend.log 2>&1 &
PIDS=("$!")

# Determine replica count
REPLICAS=$(kubectl get statefulset "$EMULATOR_STATEFULSET" -o jsonpath='{.spec.replicas}')
CONFIG=/tmp/live_instances.json
printf '[' > "$CONFIG"
for ((i=0;i<REPLICAS;i++)); do
  local_port=$((6090+i))
  kubectl port-forward pod/${EMULATOR_STATEFULSET}-${i} ${local_port}:6080 \
    >/tmp/pf_emulator_${i}.log 2>&1 &
  PIDS+=("$!")
  printf '\n  {"id":"instance-%d","streamUrl":"http://localhost:%d"}' "$i" "$local_port" >> "$CONFIG"
  if [ $i -lt $((REPLICAS-1)) ]; then
    printf ',' >> "$CONFIG"
  fi
done
printf '\n]\n' >> "$CONFIG"

printf '%s ' "${PIDS[@]}" > /tmp/live_cluster_pids

echo "Live cluster port-forwards started"
echo "Instance config written to $CONFIG"
