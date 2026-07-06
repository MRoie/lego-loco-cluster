#!/usr/bin/env bash
# scripts/create_cluster.sh -- create a Talos cluster for CI and wait for readiness
set -euo pipefail
LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/create-cluster.log"
exec > >(tee -a "$LOG_FILE") 2>&1

WORKERS=${WORKERS:-1}

echo "Creating Talos cluster with $WORKERS worker(s)" && date

# ensure docker daemon is running
if ! pgrep dockerd >/dev/null 2>&1; then
  echo "Starting Docker daemon" && date
  dockerd >"$LOG_DIR/dockerd.log" 2>&1 &
  echo "Waiting for Docker daemon to be ready" && date
  timeout=30
  while ! docker info >/dev/null 2>&1; do
    ((timeout--))
    if [ $timeout -le 0 ]; then
      echo "Docker daemon failed to start within the timeout period" && date
      exit 1
    fi
    sleep 1
  done
fi

talosctl cluster create --name loco --workers "$WORKERS" --wait

talosctl kubeconfig .
export KUBECONFIG=$PWD/kubeconfig
# Provide kubeconfig to subsequent steps in GitHub Actions
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "KUBECONFIG=$KUBECONFIG" >> "$GITHUB_ENV"
fi

echo "Deploying base manifests" && date
kubectl apply -k kustomize/base

echo "Checking initial pod status" && date
kubectl get pods -A -o wide
kubectl get nodes

echo "Waiting for pods to be ready" && date
kubectl wait --for=condition=Ready pod -A --all --timeout=300s

kubectl get pods -A -o wide

echo "Cluster setup complete" && date
