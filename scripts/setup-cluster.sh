#!/usr/bin/env bash
set -euo pipefail

echo "================================================================="
echo "🛡️  Setting up Aegis DevSecOps Cluster & Control Plane (Kind)"
echo "================================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Check prerequisites
for cmd in kind kubectl helm; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: required tool '$cmd' is not installed or not in PATH." >&2
    exit 1
  fi
done

# Create Kind Cluster
CLUSTER_NAME="aegis"
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
else
  echo "Creating Kind cluster '${CLUSTER_NAME}' with default CNI disabled..."
  kind create cluster --name "${CLUSTER_NAME}" --config "${ROOT_DIR}/kind-config.yaml"
fi

# Add Helm Repos
echo "Configuring Helm repositories..."
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts 2>/dev/null || true
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update

# Install Cilium with Hubble drop metrics
echo "Installing Cilium CNI with Hubble metrics (drop, flow, dns, tcp)..."
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --set hubble.enabled=true \
  --set hubble.metrics.enabled="{dns,drop,tcp,flow}" \
  --set prometheus.enabled=true \
  --set operator.prometheus.enabled=true

echo "Waiting for Cilium daemonset to become ready..."
kubectl -n kube-system rollout status ds/cilium --timeout=120s

# Install Cilium Tetragon (eBPF Kernel Runtime Security & Sigkill)
echo "Installing Cilium Tetragon for Kernel Runtime Security..."
helm upgrade --install tetragon cilium/tetragon \
  --namespace kube-system \
  --set tetragon.prometheus.enabled=true \
  --set tetragon.prometheus.port=2112
kubectl -n kube-system rollout status ds/tetragon --timeout=120s

# Install OPA Gatekeeper with audit metrics
echo "Installing OPA Gatekeeper with Audit metrics enabled..."
helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --set audit.metrics.enabled=true \
  --set controllerManager.metrics.enabled=true

# Install Kyverno for Supply Chain & Signature Verification
echo "Installing Kyverno Admission Controller..."
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace
kubectl -n kyverno rollout status deployment/kyverno-admission-controller --timeout=120s

# Install Argo CD
echo "Installing Argo CD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=32080 \
  --set metrics.enabled=true \
  --set server.metrics.enabled=true

# Deploy Observability Stack
echo "Deploying Observability Stack (Prometheus & Grafana)..."
kubectl apply -f "${ROOT_DIR}/k8s/observability"

# Deploy Aegis Application
echo "Deploying Aegis Application, Policies, and StatefulSet..."
kubectl apply -f "${ROOT_DIR}/k8s"

echo "================================================================="
echo "🎉 Setup Complete! Access your services:"
echo "  📊 Grafana Control Plane: http://localhost:3000 (admin / admin)"
echo "  🌐 Aegis Frontend App:    http://localhost:8080"
echo "  📈 Prometheus Server:     http://localhost:9090"
echo "  🔄 Argo CD UI:            http://localhost:8081"
echo "================================================================="
