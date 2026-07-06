#!/usr/bin/env bash
# deploy-prometheus.sh — Idempotent Prometheus Operator deployment for Lego Loco Cluster
# Installs kube-prometheus-stack, configured to discover ServiceMonitors in the loco namespace.
# Re-runnable: uses helm upgrade --install so it converges to the desired state.
set -euo pipefail

RELEASE_NAME="${PROM_RELEASE:-kube-prometheus}"
NAMESPACE="${PROM_NAMESPACE:-monitoring}"
LOCO_NAMESPACE="${LOCO_NAMESPACE:-loco}"
GRAFANA_NODEPORT="${GRAFANA_NODEPORT:-30300}"
CHART_VERSION="${PROM_CHART_VERSION:-}"  # empty = latest

echo "==> Ensuring Helm repo prometheus-community is available…"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community

echo "==> Creating namespace ${NAMESPACE} (if not exists)…"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

VERSION_FLAG=""
if [[ -n "${CHART_VERSION}" ]]; then
  VERSION_FLAG="--version ${CHART_VERSION}"
fi

echo "==> Installing / upgrading kube-prometheus-stack…"
# shellcheck disable=SC2086
helm upgrade --install "${RELEASE_NAME}" prometheus-community/kube-prometheus-stack \
  --namespace "${NAMESPACE}" \
  ${VERSION_FLAG} \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorNamespaceSelector.matchNames[0]="${LOCO_NAMESPACE}" \
  --set prometheus.prometheusSpec.serviceMonitorNamespaceSelector.matchNames[1]="${NAMESPACE}" \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleNamespaceSelector.matchNames[0]="${LOCO_NAMESPACE}" \
  --set prometheus.prometheusSpec.ruleNamespaceSelector.matchNames[1]="${NAMESPACE}" \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort="${GRAFANA_NODEPORT}" \
  --set grafana.adminPassword=loco-dev \
  --wait --timeout 5m

echo ""
echo "==> Prometheus stack deployed in namespace '${NAMESPACE}'."
echo "    Prometheus is discovering ServiceMonitors in: ${LOCO_NAMESPACE}, ${NAMESPACE}"
echo "    Grafana NodePort: ${GRAFANA_NODEPORT}  (user: admin / pass: loco-dev)"
echo ""
echo "Next steps:"
echo "  1. Deploy the loco Helm chart with monitoring.enabled=true:"
echo "     helm upgrade --install loco helm/loco-chart/ -n ${LOCO_NAMESPACE} --set monitoring.enabled=true"
echo "  2. Open Grafana: http://<node-ip>:${GRAFANA_NODEPORT}"
echo "  3. Import a dashboard or explore targets at Status → Targets in Prometheus."
