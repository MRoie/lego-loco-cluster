#!/usr/bin/env bash
# scripts/create_minikube_cluster.sh -- create a Minikube cluster for CI and wait for readiness
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/create-minikube-cluster.log"
exec > >(tee -a "$LOG_FILE") 2>&1

WORKERS=${WORKERS:-2}
KUBERNETES_VERSION=${KUBERNETES_VERSION:-v1.28.3}

echo "Creating Minikube cluster with $WORKERS nodes" && date

# Install minikube if not present
if ! command -v minikube &> /dev/null; then
    echo "Installing minikube" && date
    curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube
    sudo mv minikube /usr/local/bin/
fi

# Ensure docker daemon is running
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

# Delete existing cluster if it exists
minikube delete || true

# Start minikube cluster with specific configuration for our use case
echo "Starting Minikube cluster" && date
if ! minikube start \
    --driver=docker \
    --kubernetes-version="$KUBERNETES_VERSION" \
    --nodes="$WORKERS" \
    --cpus=4 \
    --memory=8192 \
    --disk-size=20g \
    --container-runtime=docker \
    --network-plugin=cni \
    --cni=calico \
    --feature-gates="KubeletInUserNamespace=true" \
    --wait=true; then
    
    echo "❌ Failed to start Minikube cluster" && date
    minikube logs || true
    exit 1
fi

# Enable required addons
echo "Enabling Minikube addons" && date
if ! minikube addons enable ingress; then
    echo "⚠️  Failed to enable ingress addon" && date
fi
if ! minikube addons enable metrics-server; then
    echo "⚠️  Failed to enable metrics-server addon" && date
fi
if ! minikube addons enable storage-provisioner; then
    echo "⚠️  Failed to enable storage-provisioner addon" && date
fi

# Set up kubectl context
kubectl config use-context minikube
export KUBECONFIG="$HOME/.kube/config"

# Provide kubeconfig to subsequent steps in GitHub Actions
if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "KUBECONFIG=$KUBECONFIG" >> "$GITHUB_ENV"
fi

# Wait for cluster to be fully ready
echo "Waiting for cluster components to be ready" && date
kubectl wait --for=condition=Ready node --all --timeout=300s
kubectl wait --for=condition=Ready -n kube-system --all pods --timeout=300s

echo "Deploying base manifests" && date
kubectl apply -k kustomize/base

echo "Checking initial cluster status" && date
kubectl get pods -A -o wide
kubectl get nodes -o wide

echo "Waiting for base pods to be ready" && date
kubectl wait --for=condition=Ready pod -A --all --timeout=300s

kubectl get pods -A -o wide
kubectl cluster-info

echo "Minikube cluster setup complete" && date