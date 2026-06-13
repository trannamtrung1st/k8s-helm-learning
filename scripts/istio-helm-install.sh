#!/bin/bash
set -euo pipefail

# Install Istio ambient mode with Helm (control plane + data plane + Gateway API CRDs).
# Run from repository root after kubectl context is set.
#
#   ./scripts/cert-manager-install.sh   # prerequisite (once per cluster)
#   ./scripts/istio-helm-install.sh
#   ./scripts/istio-helm-install.sh --version 1.30.1
#
# See: https://istio.io/latest/docs/ambient/install/helm/

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISTIO_VERSION="${ISTIO_VERSION:-1.30.1}"
ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
ISTIO_HELM_REPO="${ISTIO_HELM_REPO:-https://istio-release.storage.googleapis.com/charts}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
ISTIO_CSR_RELEASE="${ISTIO_CSR_RELEASE:-cert-manager-istio-csr}"
ISTIO_CSR_VERSION="${ISTIO_CSR_VERSION:-v0.14.2}"
ISTIO_CSR_CHART="${ISTIO_CSR_CHART:-oci://quay.io/jetstack/charts/cert-manager-istio-csr}"
ISTIO_CSR_VALUES="${ISTIO_CSR_VALUES:-${ROOT}/devops/platform/istio-csr-values/values.yaml}"
ISTIOD_VALUES="${ISTIOD_VALUES:-${ROOT}/devops/platform/istio-values/istiod-ambient.yaml}"
ZTUNNEL_VALUES="${ZTUNNEL_VALUES:-${ROOT}/devops/platform/istio-values/ztunnel-ambient.yaml}"
SKIP_VERIFY="false"

usage() {
  cat <<EOF
Usage: $0 [options]

Install Istio ambient mode using Helm charts (istio-base, istiod, cni, ztunnel)
and Kubernetes Gateway API CRDs.

Prerequisite: ./scripts/cert-manager-install.sh

Options:
  --version <x.y.z>     Istio chart version (default: ${ISTIO_VERSION})
  --namespace <name>    Istio namespace (default: ${ISTIO_NAMESPACE})
  --skip-verify         Skip post-install helm ls / pod checks
  -h, --help            Show this help

Environment:
  ISTIO_VERSION, ISTIO_NAMESPACE, ISTIO_HELM_REPO
  ISTIOD_VALUES, ZTUNNEL_VALUES

Standalone alternatives (not used by e2e):
  ./scripts/istio-install.sh       # istioctl profile=ambient
  ./scripts/gateway-api-install.sh # Gateway API CRDs only
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
}

require_values_files() {
  local file
  for file in "${ISTIOD_VALUES}" "${ZTUNNEL_VALUES}" "${ISTIO_CSR_VALUES}"; do
    if [[ ! -f "${file}" ]]; then
      echo "Required file not found: ${file}" >&2
      exit 1
    fi
  done
}

sync_istio_csr_istio_namespace() {
  if ! helm list -n "${CERT_MANAGER_NAMESPACE}" 2>/dev/null \
    | awk '{print $1}' | grep -qx "${ISTIO_CSR_RELEASE}"; then
    echo "Helm release ${ISTIO_CSR_RELEASE} not found (skip istio-csr namespace sync)."
    return 0
  fi

  echo "==> helm upgrade ${ISTIO_CSR_RELEASE} (control plane namespace ${ISTIO_NAMESPACE})"
  helm upgrade "${ISTIO_CSR_RELEASE}" "${ISTIO_CSR_CHART}" \
    -n "${CERT_MANAGER_NAMESPACE}" \
    --wait \
    --version "${ISTIO_CSR_VERSION}" \
    -f "${ISTIO_CSR_VALUES}" \
    --set "app.istio.namespace=${ISTIO_NAMESPACE}" \
    --set "app.controller.leaderElectionNamespace=${ISTIO_NAMESPACE}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; exit 1; }
      ISTIO_VERSION="$2"
      shift 2
      ;;
    --namespace)
      [[ $# -ge 2 ]] || { echo "Missing value for --namespace" >&2; exit 1; }
      ISTIO_NAMESPACE="$2"
      shift 2
      ;;
    --skip-verify)
      SKIP_VERIFY="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd helm
require_cmd kubectl
require_values_files

echo "==> ensure namespace ${ISTIO_NAMESPACE}"
kubectl create namespace "${ISTIO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

sync_istio_csr_istio_namespace

echo "==> helm repo add istio ${ISTIO_HELM_REPO}"
if helm repo list 2>/dev/null | grep -qE '^istio[[:space:]]'; then
  echo "Helm repo 'istio' already configured."
else
  helm repo add istio "${ISTIO_HELM_REPO}"
fi
helm repo update istio

echo "==> helm upgrade --install istio-base istio/base -n ${ISTIO_NAMESPACE} --create-namespace --wait --version ${ISTIO_VERSION}"
helm upgrade --install istio-base istio/base \
  -n "${ISTIO_NAMESPACE}" \
  --create-namespace \
  --wait \
  --version "${ISTIO_VERSION}"

echo "==> helm upgrade --install istiod istio/istiod (ambient)"
helm upgrade --install istiod istio/istiod \
  -n "${ISTIO_NAMESPACE}" \
  --set profile=ambient \
  -f "${ISTIOD_VALUES}" \
  --wait \
  --version "${ISTIO_VERSION}"

echo "==> helm upgrade --install istio-cni istio/cni -n ${ISTIO_NAMESPACE} --set profile=ambient --wait --version ${ISTIO_VERSION}"
helm upgrade --install istio-cni istio/cni \
  -n "${ISTIO_NAMESPACE}" \
  --set profile=ambient \
  --wait \
  --version "${ISTIO_VERSION}"

echo "==> helm upgrade --install ztunnel istio/ztunnel (ambient)"
helm upgrade --install ztunnel istio/ztunnel \
  -n "${ISTIO_NAMESPACE}" \
  -f "${ZTUNNEL_VALUES}" \
  --wait \
  --version "${ISTIO_VERSION}"

if [[ "${SKIP_VERIFY}" != "true" ]]; then
  echo "==> Verify Istio Helm releases"
  helm ls -n "${ISTIO_NAMESPACE}"
  echo "==> Verify Istio ambient pods"
  kubectl get pods -n "${ISTIO_NAMESPACE}"
  kubectl rollout status deployment/istiod -n "${ISTIO_NAMESPACE}" --timeout=300s
  kubectl rollout status daemonset/istio-cni-node -n "${ISTIO_NAMESPACE}" --timeout=300s
  kubectl rollout status daemonset/ztunnel -n "${ISTIO_NAMESPACE}" --timeout=300s
fi

echo "Done."
