#!/bin/bash
set -euo pipefail

# Install cert-manager (CRDs + controller, webhook, cainjector), platform-pki,
# and cert-manager istio-csr in the cert-manager namespace.
# Run from repository root.
#
#   ./scripts/gateway-api-install.sh      # prerequisite when enableGatewayAPI is true
#   ./scripts/cert-manager-install.sh
#   ./scripts/cert-manager-install.sh --version v1.20.2
#   ./scripts/cert-manager-install.sh --values devops/platform/cert-manager-values/values.yaml
#   ./scripts/cert-manager-install.sh --skip-istio-csr
#   ./scripts/cert-manager-install.sh --uninstall -y
#
# See: https://cert-manager.io/docs/installation/helm/
# istio-csr: https://cert-manager.io/docs/usage/istio-csr/installation/

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.20.2}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
CERT_MANAGER_RELEASE="${CERT_MANAGER_RELEASE:-cert-manager}"
CERT_MANAGER_CHART="${CERT_MANAGER_CHART:-oci://quay.io/jetstack/charts/cert-manager}"
CERT_MANAGER_VALUES="${CERT_MANAGER_VALUES:-${ROOT}/devops/platform/cert-manager-values/values.yaml}"
CERT_MANAGER_WAIT_TIMEOUT="${CERT_MANAGER_WAIT_TIMEOUT:-180s}"
ISTIO_CSR_VERSION="${ISTIO_CSR_VERSION:-v0.14.2}"
ISTIO_CSR_RELEASE="${ISTIO_CSR_RELEASE:-cert-manager-istio-csr}"
ISTIO_CSR_CHART="${ISTIO_CSR_CHART:-oci://quay.io/jetstack/charts/cert-manager-istio-csr}"
ISTIO_CSR_VALUES="${ISTIO_CSR_VALUES:-${ROOT}/devops/platform/istio-csr-values/values.yaml}"
ISTIO_CSR_WAIT_TIMEOUT="${ISTIO_CSR_WAIT_TIMEOUT:-180s}"
PLATFORM_PKI_CHART="${PLATFORM_PKI_CHART:-${ROOT}/devops/platform/platform-pki}"
PLATFORM_PKI_RELEASE="${PLATFORM_PKI_RELEASE:-workbench-platform-pki}"
PLATFORM_PKI_VALUES="${PLATFORM_PKI_VALUES:-${ROOT}/devops/platform/platform-values/global-values.yaml}"
ROOT_CA_CERTIFICATE="${ROOT_CA_CERTIFICATE:-workbench-root-ca}"
INTERMEDIATE_CA_CERTIFICATE="${INTERMEDIATE_CA_CERTIFICATE:-workbench-intermediate-ca}"
PKI_WAIT_TIMEOUT="${PKI_WAIT_TIMEOUT:-180s}"
SKIP_VERIFY=false
SKIP_ISTIO_CSR=false
UNINSTALL=false
AUTO_APPROVE=false

usage() {
  cat <<EOF
Usage: $0 [options]

Install or uninstall cert-manager via helm upgrade --install.
Also installs platform-pki (workbench-ca-issuer) and cert-manager istio-csr
unless --skip-istio-csr is set.

Options:
  --version <tag>         cert-manager chart version (default: ${CERT_MANAGER_VERSION})
  --istio-csr-version     istio-csr chart version (default: ${ISTIO_CSR_VERSION})
  --namespace <name>      Target namespace (default: ${CERT_MANAGER_NAMESPACE})
  --values <file>         cert-manager Helm values file
  --skip-istio-csr        Skip platform-pki bootstrap and istio-csr install
  --skip-verify           Skip post-install rollout checks
  --uninstall             Remove cert-manager and istio-csr (CRDs may remain)
  -y, --auto-approve      Skip confirmation prompt (uninstall only)
  -h, --help              Show this help

Environment:
  CERT_MANAGER_VERSION, CERT_MANAGER_NAMESPACE, CERT_MANAGER_RELEASE
  CERT_MANAGER_CHART, CERT_MANAGER_VALUES, CERT_MANAGER_WAIT_TIMEOUT
  ISTIO_CSR_VERSION, ISTIO_CSR_RELEASE, ISTIO_CSR_CHART, ISTIO_CSR_VALUES
  PLATFORM_PKI_CHART, PLATFORM_PKI_RELEASE, PLATFORM_PKI_VALUES, ROOT_CA_CERTIFICATE, INTERMEDIATE_CA_CERTIFICATE
  PKI_WAIT_TIMEOUT, ISTIO_CSR_WAIT_TIMEOUT
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

require_istio_csr_files() {
  if [[ ! -f "${ISTIO_CSR_VALUES}" ]]; then
    echo "istio-csr values file not found: ${ISTIO_CSR_VALUES}" >&2
    exit 1
  fi
  if [[ ! -f "${PLATFORM_PKI_VALUES}" ]]; then
    echo "platform-pki values file not found: ${PLATFORM_PKI_VALUES}" >&2
    exit 1
  fi
  if [[ ! -d "${PLATFORM_PKI_CHART}" ]]; then
    echo "platform-pki chart not found: ${PLATFORM_PKI_CHART}" >&2
    exit 1
  fi
}

require_gateway_api_crds() {
  if grep -qE 'enableGatewayAPI:[[:space:]]*true' "${CERT_MANAGER_VALUES}" \
    && ! kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
    echo "Gateway API CRDs are required (enableGatewayAPI: true in ${CERT_MANAGER_VALUES})." >&2
    echo "Install first: ./scripts/gateway-api-install.sh" >&2
    exit 1
  fi
}

install_cert_manager() {
  echo "==> helm upgrade --install ${CERT_MANAGER_RELEASE} cert-manager (${CERT_MANAGER_VERSION})"
  helm upgrade --install "${CERT_MANAGER_RELEASE}" "${CERT_MANAGER_CHART}" \
    -n "${CERT_MANAGER_NAMESPACE}" \
    --create-namespace \
    --version "${CERT_MANAGER_VERSION}" \
    -f "${CERT_MANAGER_VALUES}" \
    --wait

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
}

uninstall_cert_manager() {
  if helm list -n "${CERT_MANAGER_NAMESPACE}" 2>/dev/null \
    | awk '{print $1}' | grep -qx "${CERT_MANAGER_RELEASE}"; then
    echo "==> helm uninstall ${CERT_MANAGER_RELEASE}"
    helm uninstall "${CERT_MANAGER_RELEASE}" -n "${CERT_MANAGER_NAMESPACE}"
  else
    echo "Helm release ${CERT_MANAGER_RELEASE} not found (skip cert-manager uninstall)."
  fi
}

bootstrap_platform_pki() {
  echo "==> helm upgrade --install ${PLATFORM_PKI_RELEASE} platform-pki"
  helm upgrade --install "${PLATFORM_PKI_RELEASE}" "${PLATFORM_PKI_CHART}" \
    -n "${CERT_MANAGER_NAMESPACE}" \
    -f "${PLATFORM_PKI_VALUES}" \
    --set enabled=true

  echo "==> wait for ClusterIssuer/workbench-selfsigned-issuer Ready"
  kubectl wait --for=condition=Ready \
    "clusterissuer/workbench-selfsigned-issuer" \
    --timeout="${PKI_WAIT_TIMEOUT}"

  wait_for_certificate "${ROOT_CA_CERTIFICATE}"
  wait_for_certificate "${INTERMEDIATE_CA_CERTIFICATE}"
}

wait_for_certificate() {
  local name="$1"
  echo "==> wait for Certificate/${name} Ready"
  if kubectl wait --for=condition=Ready \
    "certificate/${name}" \
    -n "${CERT_MANAGER_NAMESPACE}" \
    --timeout="${PKI_WAIT_TIMEOUT}"; then
    return 0
  fi

  echo "Certificate/${name} did not become Ready within ${PKI_WAIT_TIMEOUT}." >&2
  kubectl get certificate,clusterissuer -n "${CERT_MANAGER_NAMESPACE}" >&2 || true
  kubectl get clusterissuer >&2 || true
  kubectl describe "certificate/${name}" -n "${CERT_MANAGER_NAMESPACE}" >&2 || true
  kubectl get pods -n "${CERT_MANAGER_NAMESPACE}" >&2 || true
  echo "cert-manager controller logs (last 30 lines):" >&2
  kubectl logs -n "${CERT_MANAGER_NAMESPACE}" deployment/cert-manager --tail=30 >&2 || true
  exit 1
}

require_cert_manager_running() {
  if ! kubectl get deployment cert-manager -n "${CERT_MANAGER_NAMESPACE}" >/dev/null 2>&1; then
    echo "cert-manager deployment not found in ${CERT_MANAGER_NAMESPACE}." >&2
    exit 1
  fi
  local ready="${1:-1}"
  local replicas
  replicas="$(kubectl get deployment cert-manager -n "${CERT_MANAGER_NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
  if [[ "${replicas:-0}" -lt "${ready}" ]]; then
    echo "cert-manager controller is not ready (need ${ready} ready replica(s))." >&2
    kubectl get pods -n "${CERT_MANAGER_NAMESPACE}" >&2
    kubectl logs -n "${CERT_MANAGER_NAMESPACE}" deployment/cert-manager --tail=30 >&2 || true
    exit 1
  fi
}

install_istio_csr() {
  echo "==> helm upgrade --install ${ISTIO_CSR_RELEASE} cert-manager-istio-csr (${ISTIO_CSR_VERSION})"
  helm upgrade --install "${ISTIO_CSR_RELEASE}" "${ISTIO_CSR_CHART}" \
    -n "${CERT_MANAGER_NAMESPACE}" \
    --wait \
    --version "${ISTIO_CSR_VERSION}" \
    -f "${ISTIO_CSR_VALUES}"

  if [[ "${SKIP_VERIFY}" != "true" ]]; then
    kubectl rollout status "deployment/${ISTIO_CSR_RELEASE}" \
      -n "${CERT_MANAGER_NAMESPACE}" \
      --timeout="${ISTIO_CSR_WAIT_TIMEOUT}"
  fi
}

uninstall_istio_csr() {
  if helm list -n "${CERT_MANAGER_NAMESPACE}" 2>/dev/null \
    | awk '{print $1}' | grep -qx "${ISTIO_CSR_RELEASE}"; then
    echo "==> helm uninstall ${ISTIO_CSR_RELEASE}"
    helm uninstall "${ISTIO_CSR_RELEASE}" -n "${CERT_MANAGER_NAMESPACE}"
  else
    echo "Helm release ${ISTIO_CSR_RELEASE} not found (skip istio-csr uninstall)."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; exit 1; }
      CERT_MANAGER_VERSION="$2"
      shift 2
      ;;
    --istio-csr-version)
      [[ $# -ge 2 ]] || { echo "Missing value for --istio-csr-version" >&2; exit 1; }
      ISTIO_CSR_VERSION="$2"
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
    --skip-istio-csr)
      SKIP_ISTIO_CSR=true
      shift
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
  if [[ "${AUTO_APPROVE}" != "true" ]]; then
    reply=""
    read -r -p "Delete cert-manager resources in ${CERT_MANAGER_NAMESPACE}? [y/N] " reply
    reply="$(echo "${reply}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${reply}" != "y" && "${reply}" != "yes" ]]; then
      echo "Aborted."
      exit 0
    fi
  fi

  uninstall_istio_csr
  uninstall_cert_manager
  echo "Done. Cluster-scoped CRDs and platform-pki (workbench-platform-pki) may remain."
  exit 0
fi

require_gateway_api_crds
install_cert_manager

echo "==> wait for CRD Established: certificates.cert-manager.io"
kubectl wait --for=condition=Established \
  "crd/certificates.cert-manager.io" \
  --timeout="${CERT_MANAGER_WAIT_TIMEOUT}"

if [[ "${SKIP_ISTIO_CSR}" != "true" ]]; then
  require_istio_csr_files
  require_cert_manager_running
  bootstrap_platform_pki
  install_istio_csr
  if [[ "${SKIP_VERIFY}" != "true" ]]; then
    echo "istio-csr pods:"
    kubectl get pods -n "${CERT_MANAGER_NAMESPACE}" -l app.kubernetes.io/name=cert-manager-istio-csr
  fi
else
  echo "Skip platform-pki bootstrap and istio-csr install."
fi

echo "Done."
