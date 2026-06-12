#!/bin/bash
set -euo pipefail

# Install the RabbitMQ Cluster Kubernetes Operator (CRD + controller in rabbitmq-system).
# Run from repository root.
#
#   ./scripts/rabbitmq-install.sh
#   ./scripts/rabbitmq-install.sh --version v2.21.0
#   ./scripts/rabbitmq-install.sh --uninstall -y
#
# See: https://www.rabbitmq.com/kubernetes/operator/install-operator

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RABBITMQ_OPERATOR_VERSION="${RABBITMQ_OPERATOR_VERSION:-v2.21.0}"
RABBITMQ_OPERATOR_MANIFEST="${RABBITMQ_OPERATOR_MANIFEST:-}"
RABBITMQ_OPERATOR_WAIT_TIMEOUT="${RABBITMQ_OPERATOR_WAIT_TIMEOUT:-${HELM_CRD_WAIT_TIMEOUT:-120s}}"
SKIP_VERIFY=false
UNINSTALL=false
AUTO_APPROVE=false

usage() {
  cat <<EOF
Usage: $0 [options]

Install or uninstall the RabbitMQ Cluster Kubernetes Operator.

Options:
  --version <tag>       Operator release tag (default: ${RABBITMQ_OPERATOR_VERSION})
  --manifest <url>      Override manifest URL (default: GitHub cluster-operator.yml)
  --skip-verify         Skip post-install pod rollout checks
  --uninstall           Remove operator resources via kubectl delete
  -y, --auto-approve    Skip confirmation prompt (uninstall only)
  -h, --help            Show this help

Environment:
  RABBITMQ_OPERATOR_VERSION, RABBITMQ_OPERATOR_MANIFEST
  RABBITMQ_OPERATOR_WAIT_TIMEOUT  kubectl wait for CRD Established (default: 120s)
  HELM_CRD_WAIT_TIMEOUT           Optional alias for wait timeout
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
}

resolve_manifest() {
  if [[ -z "${RABBITMQ_OPERATOR_MANIFEST}" ]]; then
    RABBITMQ_OPERATOR_MANIFEST="https://github.com/rabbitmq/cluster-operator/releases/download/${RABBITMQ_OPERATOR_VERSION}/cluster-operator.yml"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; exit 1; }
      RABBITMQ_OPERATOR_VERSION="$2"
      shift 2
      ;;
    --manifest)
      [[ $# -ge 2 ]] || { echo "Missing value for --manifest" >&2; exit 1; }
      RABBITMQ_OPERATOR_MANIFEST="$2"
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

resolve_manifest
require_cmd kubectl

if [[ "${UNINSTALL}" == "true" ]]; then
  if ! kubectl get crd rabbitmqclusters.rabbitmq.com >/dev/null 2>&1; then
    echo "RabbitMQ Cluster Operator CRD not found (skip uninstall)."
    exit 0
  fi

  if [[ "${AUTO_APPROVE}" != "true" ]]; then
    reply=""
    read -r -p "Delete RabbitMQ Cluster Operator resources from ${RABBITMQ_OPERATOR_MANIFEST}? [y/N] " reply
    reply="$(echo "${reply}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${reply}" != "y" && "${reply}" != "yes" ]]; then
      echo "Aborted."
      exit 0
    fi
  fi

  echo "==> kubectl delete -f ${RABBITMQ_OPERATOR_MANIFEST}"
  kubectl delete -f "${RABBITMQ_OPERATOR_MANIFEST}" --ignore-not-found
  echo "Done."
  exit 0
fi

if kubectl get crd rabbitmqclusters.rabbitmq.com >/dev/null 2>&1; then
  echo "RabbitMQ CRD rabbitmqclusters.rabbitmq.com already installed (skip apply)."
else
  echo "==> kubectl apply -f ${RABBITMQ_OPERATOR_MANIFEST}"
  kubectl apply -f "${RABBITMQ_OPERATOR_MANIFEST}"
fi

echo "==> wait for CRD Established: rabbitmqclusters.rabbitmq.com"
kubectl wait --for=condition=Established \
  "crd/rabbitmqclusters.rabbitmq.com" \
  --timeout="${RABBITMQ_OPERATOR_WAIT_TIMEOUT}"

if [[ "${SKIP_VERIFY}" != "true" ]]; then
  echo "RabbitMQ operator pods:"
  kubectl get pods -n rabbitmq-system
  if kubectl get deployment rabbitmq-cluster-operator -n rabbitmq-system >/dev/null 2>&1; then
    kubectl rollout status deployment/rabbitmq-cluster-operator -n rabbitmq-system --timeout="${RABBITMQ_OPERATOR_WAIT_TIMEOUT}"
  fi
fi

echo "Done."
