#!/bin/bash
set -euo pipefail

# Install Kubernetes Gateway API CRDs (required for Istio Gateway / HTTPRoute).
# Run from repository root.
#
#   ./scripts/gateway-api-install.sh
#   ./scripts/gateway-api-install.sh --version v1.5.1
#
# See: https://istio.io/latest/docs/ambient/install/helm/

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.5.1}"
GATEWAY_API_MANIFEST="${GATEWAY_API_MANIFEST:-}"

usage() {
  cat <<EOF
Usage: $0 [options]

Install Kubernetes Gateway API CRDs (experimental bundle used by Istio ambient getting started).

Options:
  --version <tag>     Gateway API release tag (default: ${GATEWAY_API_VERSION})
  --manifest <url>    Override manifest URL (default: GitHub experimental-install.yaml)
  -h, --help          Show this help

Environment:
  GATEWAY_API_VERSION, GATEWAY_API_MANIFEST
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
      GATEWAY_API_VERSION="$2"
      shift 2
      ;;
    --manifest)
      [[ $# -ge 2 ]] || { echo "Missing value for --manifest" >&2; exit 1; }
      GATEWAY_API_MANIFEST="$2"
      shift 2
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

if [[ -z "${GATEWAY_API_MANIFEST}" ]]; then
  GATEWAY_API_MANIFEST="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml"
fi

require_cmd kubectl

if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  echo "Gateway API CRD gateways.gateway.networking.k8s.io already installed (skip apply)."
else
  echo "==> kubectl apply --server-side -f ${GATEWAY_API_MANIFEST}"
  kubectl apply --server-side -f "${GATEWAY_API_MANIFEST}"
fi

echo "Gateway API CRDs:"
kubectl get crd 2>/dev/null | grep 'gateway.networking.k8s.io' || true

echo "Done."
