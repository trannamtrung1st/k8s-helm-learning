#!/bin/bash
set -euo pipefail

# Install cert-manager (CRDs + controller, webhook, cainjector in cert-manager namespace).
# Run from repository root.
#
#   ./scripts/cert-manager-install.sh
#   ./scripts/cert-manager-install.sh --version v1.20.2
#   ./scripts/cert-manager-install.sh --values devops/platform/cert-manager-values/values.yaml
#   ./scripts/cert-manager-install.sh --uninstall -y
#
# Renders the upstream OCI Helm chart and applies with kubectl (see cert-manager docs:
# https://cert-manager.io/docs/installation/helm/#output-yaml).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.20.2}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
CERT_MANAGER_RELEASE="${CERT_MANAGER_RELEASE:-cert-manager}"
CERT_MANAGER_CHART="${CERT_MANAGER_CHART:-oci://quay.io/jetstack/charts/cert-manager}"
CERT_MANAGER_VALUES="${CERT_MANAGER_VALUES:-${ROOT}/devops/platform/cert-manager-values/values.yaml}"
CERT_MANAGER_WAIT_TIMEOUT="${CERT_MANAGER_WAIT_TIMEOUT:-180s}"
SKIP_VERIFY=false
UNINSTALL=false
AUTO_APPROVE=false

usage() {
  cat <<EOF
Usage: $0 [options]

Install or uninstall cert-manager via helm template + kubectl apply.

Options:
  --version <tag>       Chart version (default: ${CERT_MANAGER_VERSION})
  --namespace <name>    Target namespace (default: ${CERT_MANAGER_NAMESPACE})
  --values <file>       Helm values file (default: cert-manager-values/values.yaml)
  --skip-verify         Skip post-install rollout checks
  --uninstall           Remove cert-manager resources (CRDs may remain)
  -y, --auto-approve    Skip confirmation prompt (uninstall only)
  -h, --help            Show this help

Environment:
  CERT_MANAGER_VERSION, CERT_MANAGER_NAMESPACE, CERT_MANAGER_RELEASE
  CERT_MANAGER_CHART    OCI chart reference (default: quay.io/jetstack/charts/cert-manager)
  CERT_MANAGER_VALUES
  CERT_MANAGER_WAIT_TIMEOUT
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
}

require_values_file() {
  if [[ ! -f "${CERT_MANAGER_VALUES}" ]]; then
    echo "cert-manager values file not found: ${CERT_MANAGER_VALUES}" >&2
    exit 1
  fi
}

render_manifest() {
  helm template "${CERT_MANAGER_RELEASE}" "${CERT_MANAGER_CHART}" \
    --namespace "${CERT_MANAGER_NAMESPACE}" \
    --version "${CERT_MANAGER_VERSION}" \
    -f "${CERT_MANAGER_VALUES}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; exit 1; }
      CERT_MANAGER_VERSION="$2"
      shift 2
      ;;
    --namespace)
      [[ $# -ge 2 ]] || { echo "Missing value for --namespace" >&2; exit 1; }
      CERT_MANAGER_NAMESPACE="$2"
      shift 2
      ;;
    --values)
      [[ $# -ge 2 ]] || { echo "Missing value for --values" >&2; exit 1; }
      CERT_MANAGER_VALUES="$2"
      shift 2
      ;;
    --skip-verify)
      SKIP_VERIFY=true
      shift
      ;;
    --uninstall)
      UNINSTALL=true
      shift
      ;;
    -y|--auto-approve)
      AUTO_APPROVE=true
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
require_values_file

if [[ "${UNINSTALL}" == "true" ]]; then
  if ! kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
    echo "cert-manager CRD not found (skip uninstall)."
    exit 0
  fi

  if [[ "${AUTO_APPROVE}" != "true" ]]; then
    reply=""
    read -r -p "Delete cert-manager resources in ${CERT_MANAGER_NAMESPACE}? [y/N] " reply
    reply="$(echo "${reply}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${reply}" != "y" && "${reply}" != "yes" ]]; then
      echo "Aborted."
      exit 0
    fi
  fi

  echo "==> helm template | kubectl delete (cert-manager ${CERT_MANAGER_VERSION})"
  render_manifest | kubectl delete -f - --ignore-not-found
  echo "Done. Cluster-scoped CRDs may remain (cert-manager default uninstall policy)."
  exit 0
fi

echo "==> ensure namespace ${CERT_MANAGER_NAMESPACE}"
kubectl create namespace "${CERT_MANAGER_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

if kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
  echo "cert-manager CRD certificates.cert-manager.io already installed (skip apply)."
else
  echo "==> helm template | kubectl apply (cert-manager ${CERT_MANAGER_VERSION})"
  render_manifest | kubectl apply -f -
fi

echo "==> wait for CRD Established: certificates.cert-manager.io"
kubectl wait --for=condition=Established \
  "crd/certificates.cert-manager.io" \
  --timeout="${CERT_MANAGER_WAIT_TIMEOUT}"

if [[ "${SKIP_VERIFY}" != "true" ]]; then
  echo "cert-manager pods:"
  kubectl get pods -n "${CERT_MANAGER_NAMESPACE}"
  for deploy in cert-manager cert-manager-webhook cert-manager-cainjector; do
    if kubectl get deployment "${deploy}" -n "${CERT_MANAGER_NAMESPACE}" >/dev/null 2>&1; then
      kubectl rollout status "deployment/${deploy}" -n "${CERT_MANAGER_NAMESPACE}" \
        --timeout="${CERT_MANAGER_WAIT_TIMEOUT}"
    fi
  done
fi

echo "Done."
