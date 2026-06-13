#!/bin/bash
set -euo pipefail

# Export the workbench root CA certificate from cert-manager for local trust installation.
# Only the public certificate (tls.crt) is written — never the CA private key.
#
# Run from repository root after platform-pki is deployed (./scripts/helm-apply.sh).
#
#   ./scripts/cert-manager-export-root-ca.sh
#   ./scripts/cert-manager-export-root-ca.sh --cluster local
#   ./scripts/cert-manager-export-root-ca.sh --output ~/workbench-root-ca.crt
#   ./scripts/cert-manager-export-root-ca.sh --install-trust
#   ./scripts/cert-manager-export-root-ca.sh --install-trust --keychain login
#
# Defaults match devops/platform/platform-values/global-values.yaml (workbenchPki.rootCa).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
ROOT_CA_SECRET="${ROOT_CA_SECRET:-workbench-root-ca-secret}"
ROOT_CA_CERTIFICATE="${ROOT_CA_CERTIFICATE:-workbench-root-ca}"
OUTPUT="${OUTPUT:-${ROOT}/.temp/workbench-root-ca.crt}"
CLUSTER=""
SKIP_CONTEXT_SWITCH=false
INSTALL_TRUST=false
KEYCHAIN="${KEYCHAIN:-system}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-120s}"
SKIP_WAIT=false

usage() {
  cat <<EOF
Usage: $0 [options]

Export the workbench root CA (public cert only) from a cert-manager TLS secret.

Options:
  --cluster <name>        Switch kubectl context via devops/clusters/<name>/cluster.conf
  --context <name>        kubectl context (overrides cluster.conf; also KUBECTL_CONTEXT)
  --skip-context-switch   Do not change kubectl context
  --namespace <name>      cert-manager namespace (default: ${CERT_MANAGER_NAMESPACE})
  --secret <name>         TLS secret name (default: ${ROOT_CA_SECRET})
  --certificate <name>    Certificate resource to wait for (default: ${ROOT_CA_CERTIFICATE})
  --output <path>         Output PEM file (default: .temp/workbench-root-ca.crt)
  --install-trust         Import into local trust store (macOS Keychain / Linux ca-certificates)
  --keychain <login|system>
                          macOS keychain for --install-trust (default: system, requires sudo)
  --skip-wait             Do not wait for Certificate Ready before export
  --wait-timeout <dur>    kubectl wait timeout (default: ${WAIT_TIMEOUT})
  -h, --help              Show this help

Environment:
  CERT_MANAGER_NAMESPACE, ROOT_CA_SECRET, ROOT_CA_CERTIFICATE, OUTPUT, WAIT_TIMEOUT
  KUBECTL_CONTEXT, HELM_SKIP_CONTEXT_SWITCH=1

After export, trust the CA so browsers accept https://localhost and *.k8slearning.com
certs signed by the workbench intermediate CA.

macOS login keychain (manual, no sudo):
  security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db <file>

macOS system keychain (manual, all users):
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <file>

Linux Debian/Ubuntu (manual):
  sudo cp <file> /usr/local/share/ca-certificates/workbench-root-ca.crt
  sudo update-ca-certificates
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
    --cluster)
      [[ $# -ge 2 ]] || { echo "Missing value for --cluster" >&2; exit 1; }
      CLUSTER="$2"
      shift 2
      ;;
    --context)
      [[ $# -ge 2 ]] || { echo "Missing value for --context" >&2; exit 1; }
      KUBECTL_CONTEXT="$2"
      shift 2
      ;;
    --skip-context-switch)
      SKIP_CONTEXT_SWITCH=true
      shift
      ;;
    --namespace)
      [[ $# -ge 2 ]] || { echo "Missing value for --namespace" >&2; exit 1; }
      CERT_MANAGER_NAMESPACE="$2"
      shift 2
      ;;
    --secret)
      [[ $# -ge 2 ]] || { echo "Missing value for --secret" >&2; exit 1; }
      ROOT_CA_SECRET="$2"
      shift 2
      ;;
    --certificate)
      [[ $# -ge 2 ]] || { echo "Missing value for --certificate" >&2; exit 1; }
      ROOT_CA_CERTIFICATE="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 1; }
      OUTPUT="$2"
      shift 2
      ;;
    --install-trust)
      INSTALL_TRUST=true
      shift
      ;;
    --keychain)
      [[ $# -ge 2 ]] || { echo "Missing value for --keychain" >&2; exit 1; }
      KEYCHAIN="$2"
      shift 2
      ;;
    --skip-wait)
      SKIP_WAIT=true
      shift
      ;;
    --wait-timeout)
      [[ $# -ge 2 ]] || { echo "Missing value for --wait-timeout" >&2; exit 1; }
      WAIT_TIMEOUT="$2"
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

require_cmd kubectl
require_cmd base64

if [[ "${SKIP_CONTEXT_SWITCH}" != "true" && "${HELM_SKIP_CONTEXT_SWITCH:-0}" != "1" && -n "${CLUSTER}" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT}/scripts/lib/helm-kubectl-context.sh"
  helm_kubectl_use_context "${CLUSTER}"
fi

if [[ "${SKIP_WAIT}" != "true" ]]; then
  if kubectl get certificate "${ROOT_CA_CERTIFICATE}" -n "${CERT_MANAGER_NAMESPACE}" >/dev/null 2>&1; then
    echo "==> wait for Certificate/${ROOT_CA_CERTIFICATE} Ready"
    kubectl wait --for=condition=Ready \
      "certificate/${ROOT_CA_CERTIFICATE}" \
      -n "${CERT_MANAGER_NAMESPACE}" \
      --timeout="${WAIT_TIMEOUT}"
  else
    echo "Certificate/${ROOT_CA_CERTIFICATE} not found in ${CERT_MANAGER_NAMESPACE}; waiting for secret only."
  fi
fi

if ! kubectl get secret "${ROOT_CA_SECRET}" -n "${CERT_MANAGER_NAMESPACE}" >/dev/null 2>&1; then
  echo "Secret ${ROOT_CA_SECRET} not found in namespace ${CERT_MANAGER_NAMESPACE}." >&2
  echo "Deploy platform-pki first: ./scripts/helm-apply.sh" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT}")"

echo "==> export tls.crt from secret/${ROOT_CA_SECRET} (${CERT_MANAGER_NAMESPACE})"
kubectl get secret "${ROOT_CA_SECRET}" -n "${CERT_MANAGER_NAMESPACE}" \
  -o jsonpath='{.data.tls\.crt}' | base64 -d >"${OUTPUT}"

if [[ ! -s "${OUTPUT}" ]]; then
  echo "Export failed: ${OUTPUT} is empty." >&2
  exit 1
fi

echo "Wrote root CA certificate: ${OUTPUT}"

install_trust_macos() {
  local cert_file="$1"
  local keychain_path

  case "${KEYCHAIN}" in
    login)
      keychain_path="${HOME}/Library/Keychains/login.keychain-db"
      echo "==> install trust (macOS login keychain)"
      ;;
    system)
      keychain_path="/Library/Keychains/System.keychain"
      echo "==> install trust (macOS system keychain)"
      ;;
    *)
      echo "Invalid --keychain value: ${KEYCHAIN} (use login or system)" >&2
      exit 1
      ;;
  esac

  if [[ ! -f "${keychain_path}" ]]; then
    echo "Keychain not found: ${keychain_path}" >&2
    exit 1
  fi

  if [[ "${KEYCHAIN}" == "system" ]]; then
    sudo security add-trusted-cert -d -r trustRoot \
      -k "${keychain_path}" "${cert_file}"
  else
    security add-trusted-cert -d -r trustRoot \
      -k "${keychain_path}" "${cert_file}"
  fi
}

install_trust_linux() {
  local cert_file="$1"
  local dest="/usr/local/share/ca-certificates/workbench-root-ca.crt"
  echo "==> install trust (Linux ca-certificates)"
  sudo cp "${cert_file}" "${dest}"
  sudo update-ca-certificates
}

if [[ "${INSTALL_TRUST}" == "true" ]]; then
  case "$(uname -s)" in
    Darwin)
      install_trust_macos "${OUTPUT}"
      ;;
    Linux)
      install_trust_linux "${OUTPUT}"
      ;;
    *)
      echo "Unsupported OS for --install-trust: $(uname -s)" >&2
      echo "Install manually using the commands from --help." >&2
      exit 1
      ;;
  esac
  echo "Root CA installed in local trust store."
else
  echo ""
  echo "To trust locally (pick one):"
  echo "  $0 --install-trust"
  echo "  macOS (system keychain): sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${OUTPUT}"
  echo "  macOS (login keychain):  security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db ${OUTPUT}"
  echo "  Linux:  sudo cp ${OUTPUT} /usr/local/share/ca-certificates/workbench-root-ca.crt && sudo update-ca-certificates"
fi

echo "Done."
