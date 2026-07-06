# Cluster Setup Guide

**Date**: 2026-03-27
**Author**: @k8s-lead
**Task**: K5
**Status**: finding

## Summary

This guide covers setting up a local Kubernetes cluster for the Lego Loco Cluster project using either KIND (preferred for CI) or minikube (convenient for dev). Both support the 9-replica StatefulSet of QEMU Windows 98 emulators.

---

## KIND vs minikube Comparison

| Feature | KIND | minikube |
|---------|------|----------|
| **Best for** | CI pipelines, multi-node testing | Local development, quick iteration |
| **Startup time** | ~30s (single node), ~60s (multi-node) | ~90s (first start), ~30s (cached) |
| **Multi-node** | Yes, first-class (configurable workers) | Limited (experimental `--nodes`) |
| **NetworkPolicy** | Yes (Calico/Cilium CNI installable) | Yes (Calico addon) |
| **NET_ADMIN capability** | Requires extra config in kind-config.yaml | Works with `--extra-config` |
| **Docker-in-Docker** | Runs as Docker containers — no VM overhead | Runs a VM (or Docker driver, lighter) |
| **Port forwarding** | Uses `extraPortMappings` in config | `--ports` flag or `minikube service` |
| **VNC access** | Forward ports 5900-5908 via extraPortMappings | `minikube service` or NodePort |
| **Image loading** | `kind load docker-image` (fast, no registry) | `minikube image load` (similar) |
| **Persistent volumes** | hostPath via `extraMounts` in kind-config | Built-in hostPath provisioner |
| **CI integration** | Widely used in GitHub Actions | Possible but slower startup |
| **Resource overhead** | ~200MB base + pods | ~1GB base VM + pods |
| **Cleanup** | `kind delete cluster` (instant) | `minikube delete` (instant) |

### Recommendation

- **CI / GitHub Actions**: Use KIND — faster startup, lower overhead, native multi-node.
- **Local development**: Use minikube with Docker driver — easier VNC port forwarding, built-in dashboard.
- **NetworkPolicy testing**: Either works; KIND + Calico is more production-like.

---

## KIND Setup (Step-by-Step)

### Prerequisites

```bash
# Install KIND
go install sigs.k8s.io/kind@latest
# or: brew install kind / choco install kind

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/$(uname -s | tr '[:upper:]' '[:lower:]')/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 1. Create Cluster

Use the project's KIND config at `k8s/kind-config.yaml`:

```bash
kind create cluster --name loco --config k8s/kind-config.yaml
```

If no config exists, create a minimal one:

```yaml
# k8s/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      # VNC ports for 9 instances
      - containerPort: 30900
        hostPort: 5900
        protocol: TCP
      - containerPort: 30901
        hostPort: 5901
        protocol: TCP
      - containerPort: 30902
        hostPort: 5902
        protocol: TCP
      - containerPort: 30903
        hostPort: 5903
        protocol: TCP
      - containerPort: 30904
        hostPort: 5904
        protocol: TCP
      - containerPort: 30905
        hostPort: 5905
        protocol: TCP
      - containerPort: 30906
        hostPort: 5906
        protocol: TCP
      - containerPort: 30907
        hostPort: 5907
        protocol: TCP
      - containerPort: 30908
        hostPort: 5908
        protocol: TCP
      # Frontend
      - containerPort: 30080
        hostPort: 3000
        protocol: TCP
      # Backend API
      - containerPort: 30081
        hostPort: 3001
        protocol: TCP
    extraMounts:
      - hostPath: /tmp/loco-art-shared
        containerPath: /tmp/loco-art-shared
```

### 2. Install Calico (for NetworkPolicy Support)

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=120s
```

### 3. Load Container Images

```bash
# Build emulator image
docker build -t ghcr.io/mroie/qemu-softgpu:latest containers/qemu-softgpu/

# Load into KIND (no registry needed)
kind load docker-image ghcr.io/mroie/qemu-softgpu:latest --name loco

# Load frontend and backend images
docker build -t ghcr.io/mroie/loco-frontend:latest frontend/
docker build -t ghcr.io/mroie/loco-backend:latest backend/
kind load docker-image ghcr.io/mroie/loco-frontend:latest --name loco
kind load docker-image ghcr.io/mroie/loco-backend:latest --name loco
```

### 4. Create Namespace and Deploy with Helm

```bash
kubectl create namespace loco

# Deploy using Helm with KIND-appropriate values
helm install loco helm/loco-chart/ \
  --namespace loco \
  --values helm/loco-chart/values.yaml \
  --set storage.hostPath.enabled=true \
  --set storage.hostPath.path=/tmp/loco-art-shared

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=emulator \
  -n loco --timeout=300s
```

### 5. Apply NetworkPolicy for Game Ports

```bash
kubectl apply -f k8s/networkpolicy-game-ports.yaml -n loco
```

### 6. Verify Deployment

```bash
# Check all 9 emulator pods are running
kubectl get pods -n loco -l app.kubernetes.io/component=emulator

# Check services
kubectl get svc -n loco

# Test backend health
kubectl port-forward svc/loco-backend 3001:3001 -n loco &
curl http://localhost:3001/health
```

### KIND Cleanup

```bash
kind delete cluster --name loco
```

---

## minikube Setup (Step-by-Step)

### Prerequisites

```bash
# Install minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# kubectl and helm — same as KIND section above
```

### 1. Start Cluster

```bash
# Docker driver (recommended — lighter than VM)
minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=8192 \
  --disk-size=30g \
  --kubernetes-version=v1.29.0 \
  --extra-config=apiserver.enable-admission-plugins=PodSecurityPolicy

# Enable required addons
minikube addons enable metrics-server
minikube addons enable storage-provisioner
```

### 2. Load Images

```bash
# Build and load (similar to KIND)
minikube image load ghcr.io/mroie/qemu-softgpu:latest
minikube image load ghcr.io/mroie/loco-frontend:latest
minikube image load ghcr.io/mroie/loco-backend:latest
```

### 3. Deploy with Helm (minikube Values)

```bash
kubectl create namespace loco

helm install loco helm/loco-chart/ \
  --namespace loco \
  --values helm/loco-chart/values-minikube.yaml
```

### 4. Access Services

```bash
# VNC port forwarding for all 9 instances
for i in $(seq 0 8); do
  kubectl port-forward "pod/loco-emulator-$i" "$((5900 + i)):5901" -n loco &
done

# Frontend
minikube service loco-frontend -n loco --url

# Backend
minikube service loco-backend -n loco --url
```

### minikube Cleanup

```bash
minikube delete
```

---

## Common Gotchas

### NET_ADMIN Capability

QEMU TAP/bridge networking requires `NET_ADMIN` inside the pod. Both the entrypoint scripts (`containers/qemu/entrypoint.sh`, `containers/qemu-softgpu/entrypoint.sh`) create TAP interfaces and bridges at runtime.

```yaml
# In your pod spec or Helm values:
securityContext:
  capabilities:
    add: ["NET_ADMIN"]
```

**KIND**: Works out of the box — containers run as root by default.
**minikube**: Docker driver works. VirtualBox driver may need `--extra-config=kubelet.allowed-unsafe-sysctls=net.*`.

### Bridge Networking Inside Pods

Each emulator pod creates its own `loco-br` bridge and `tapN` interface. This is isolated per pod — bridges do **not** span across pods. Cross-instance traffic goes through Kubernetes pod networking, not through a shared bridge.

For LAN multiplayer, instances communicate via their pod IPs on the Kubernetes overlay network, not via the `192.168.10.x` bridge IPs. The bridge network is internal to each pod (QEMU ↔ bridge ↔ TAP). Cross-pod game traffic (port 2300, 47624) uses `NetworkPolicy` to allow ingress/egress.

### DNS Resolution

- **Kubernetes DNS**: Pods in a StatefulSet get stable DNS names: `loco-emulator-0.loco-emulator.loco.svc.cluster.local`
- **Win98 DNS**: Not used — NetBIOS name resolution handles instance discovery within the game
- **dnsmasq**: Not needed if using static IPs (see `2026-03-27-dhcp-collision-prevention.md`)

### Image Pull Policy

When using `kind load` or `minikube image load`, set `imagePullPolicy: Never` or `IfNotPresent` to avoid pulling from a remote registry:

```yaml
# In Helm values or pod spec:
image:
  pullPolicy: IfNotPresent
```

### Resource Requirements

9 QEMU instances are resource-intensive:

| Resource | Per Instance | Total (9 instances) |
|----------|-------------|---------------------|
| CPU | ~0.5 core (TCG) | ~4.5 cores |
| Memory | ~768MB (512 guest + overhead) | ~7GB |
| Disk | ~2GB qcow2 snapshot | ~18GB |

Ensure your host machine has at least 8 cores, 16GB RAM, and 30GB disk for a full 9-instance deployment. For development, scale down to 2-3 replicas.

---

## Helm Chart Deployment Commands Reference

```bash
# Install (fresh)
helm install loco helm/loco-chart/ -n loco -f helm/loco-chart/values.yaml

# Upgrade (update existing)
helm upgrade loco helm/loco-chart/ -n loco -f helm/loco-chart/values.yaml

# Dry-run (preview manifest without applying)
helm install loco helm/loco-chart/ -n loco --dry-run --debug

# With specific values file
helm install loco helm/loco-chart/ -n loco -f helm/loco-chart/values-minikube.yaml

# With value overrides
helm install loco helm/loco-chart/ -n loco \
  --set replicas=3 \
  --set storage.hostPath.enabled=true

# Uninstall
helm uninstall loco -n loco

# List releases
helm list -n loco

# Check status
helm status loco -n loco
```

## Cross-References

- **K2**: 9-replica validation — `docs/knowledge/k8s-infra/2026-03-27-9-replica-validation.md`
- **K3**: NetworkPolicy — `docs/knowledge/k8s-infra/2026-03-27-networkpolicy-game-ports.md`
- **L2**: Instance identity — `docs/knowledge/lan-networking/instance-identity-spec.md`
- **L7**: DHCP prevention — `docs/knowledge/lan-networking/2026-03-27-dhcp-collision-prevention.md`
- **E4**: QEMU hardware — `docs/knowledge/emulation/qemu-hardware-reference.md`
