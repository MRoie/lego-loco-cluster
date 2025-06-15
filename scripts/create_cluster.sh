#!/usr/bin/env bash
# scripts/create_cluster.sh -- create a Talos cluster for CI and wait for readiness
set -euo pipefail
LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/create-cluster.log"
exec > >(tee -a "$LOG_FILE") 2>&1

WORKERS=${WORKERS:-1}

echo "Creating Talos cluster with $WORKERS worker(s)" && date

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
kubectl wait --for=condition=Ready pod --all --timeout=300s

kubectl get pods -A -o wide

echo "Cluster setup complete" && date
