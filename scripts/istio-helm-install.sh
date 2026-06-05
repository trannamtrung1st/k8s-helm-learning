#!/bin/bash
set -euo pipefail

# Install Istio ambient mode with Helm (control plane + data plane + Gateway API CRDs).
# Run from repository root after kubectl context is set.
#
#   ./scripts/istio-helm-install.sh
#   ./scripts/istio-helm-install.sh --version 1.30.1
#
# See: https://istio.io/latest/docs/ambient/install/helm/

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISTIO_VERSION="${ISTIO_VERSION:-1.30.1}"
ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
ISTIO_HELM_REPO="${ISTIO_HELM_REPO:-https://istio-release.storage.googleapis.com/charts}"
SKIP_VERIFY="false"

usage() {
  cat <<EOF
Usage: $0 [options]

Install Istio ambient mode using Helm charts (istio-base, istiod, cni, ztunnel)
and Kubernetes Gateway API CRDs per the official ambient Helm guide.

Options:
  --version <x.y.z>     Istio chart version (default: ${ISTIO_VERSION})
  --namespace <name>    Istio namespace (default: ${ISTIO_NAMESPACE})
  --skip-verify         Skip post-install helm ls / pod checks
  -h, --help            Show this help

Environment:
  ISTIO_VERSION, ISTIO_NAMESPACE, ISTIO_HELM_REPO

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

echo "==> helm repo add istio ${ISTIO_HELM_REPO}"
if helm repo list -o json 2>/dev/null | rg -q '"name":"istio"'; then
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

echo "==> install Kubernetes Gateway API CRDs"
"${ROOT}/scripts/gateway-api-install.sh"

echo "==> helm upgrade --install istiod istio/istiod -n ${ISTIO_NAMESPACE} --set profile=ambient --wait --version ${ISTIO_VERSION}"
helm upgrade --install istiod istio/istiod \
  -n "${ISTIO_NAMESPACE}" \
  --set profile=ambient \
  --wait \
  --version "${ISTIO_VERSION}"

echo "==> helm upgrade --install istio-cni istio/cni -n ${ISTIO_NAMESPACE} --set profile=ambient --wait --version ${ISTIO_VERSION}"
helm upgrade --install istio-cni istio/cni \
  -n "${ISTIO_NAMESPACE}" \
  --set profile=ambient \
  --wait \
  --version "${ISTIO_VERSION}"

echo "==> helm upgrade --install ztunnel istio/ztunnel -n ${ISTIO_NAMESPACE} --wait --version ${ISTIO_VERSION}"
helm upgrade --install ztunnel istio/ztunnel \
  -n "${ISTIO_NAMESPACE}" \
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
