#!/usr/bin/env bash
# Update the active emulator instance across the stack
set -euo pipefail
if [ $# -ne 1 ]; then
  echo "Usage: $0 <instance-id>" >&2
  exit 1
fi
ID="$1"
CONFIG_DIR="${CONFIG_DIR:-$(dirname "$0")/../config}"
ACTIVE_FILE="$CONFIG_DIR/active.json"
mkdir -p "$CONFIG_DIR"
echo "{\"active\": \"$ID\"}" > "$ACTIVE_FILE"
echo "Active instance set to $ID"
# Propagate annotation to Kubernetes pods if kubectl is available
if command -v kubectl >/dev/null 2>&1; then
  kubectl annotate pods -l app=loco-loco-emulator active-instance="$ID" --overwrite >/dev/null || true
fi

# Adjust CPU quotas of emulator containers when using Docker
FOCUSED_CPUS="${FOCUSED_CPUS:-1}"
UNFOCUSED_CPUS="${UNFOCUSED_CPUS:-0.25}"
if command -v docker >/dev/null 2>&1; then
  for c in $(docker ps --format '{{.Names}}' | grep -E '^loco-emulator-[0-9]+$'); do
    if [[ "$c" == *"$ID" ]]; then
      docker update --cpus "$FOCUSED_CPUS" "$c" >/dev/null || true
    else
      docker update --cpus "$UNFOCUSED_CPUS" "$c" >/dev/null || true
    fi
  done
fi

