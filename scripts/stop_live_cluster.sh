#!/usr/bin/env bash
# Stop port-forwards for the live cluster
echo "Stopping live cluster forwards"
set -euo pipefail
if [ -f /tmp/live_cluster_pids ]; then
  for pid in $(cat /tmp/live_cluster_pids); do
    kill "$pid" >/dev/null 2>&1 || true
  done
  rm -f /tmp/live_cluster_pids
fi
kubectl delete -k kustomize/base >/dev/null 2>&1 || true
echo "Live cluster stopped"
