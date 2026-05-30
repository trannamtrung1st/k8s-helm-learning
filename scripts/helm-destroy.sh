#!/bin/bash
set -euo pipefail

# Uninstall the Workbench Helm releases from the target cluster (main umbrella, then CRDs umbrella).
# Run from repository root. Requires helm and kubectl context.
#
#   ./scripts/helm-destroy.sh
#   ./scripts/helm-destroy.sh --cluster local
#   ./scripts/helm-destroy.sh --cluster aks -y
#
# Switches kubectl context from devops/clusters/<cluster>/cluster.conf before uninstall
# (same as helm-apply.sh). Override release or namespace:
#   HELM_RELEASE=workbench-umbrella-aks ./scripts/helm-destroy.sh --cluster aks
#   HELM_CRDS_RELEASE=workbench-crds-umbrella-aks ./scripts/helm-destroy.sh --cluster aks
#   HELM_CRDS_NAMESPACE=kube-system ./scripts/helm-destroy.sh --cluster local
#   HELM_NAMESPACE=workbench-platform ./scripts/helm-destroy.sh --cluster local
#
# Cluster-scoped CRDs installed by the operator may remain after uninstall; delete manually if needed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM_CLUSTER="${HELM_CLUSTER:-local}"
HELM_RELEASE="${HELM_RELEASE:-}"
HELM_CRDS_RELEASE="${HELM_CRDS_RELEASE:-}"
HELM_CRDS_NAMESPACE="${HELM_CRDS_NAMESPACE:-kube-system}"
HELM_NAMESPACE="${HELM_NAMESPACE:-workbench-platform}"
HELM_SKIP_CONTEXT_SWITCH="${HELM_SKIP_CONTEXT_SWITCH:-0}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"
AUTO_APPROVE=false
HELM_WAIT=false
HELM_KEEP_HISTORY=false

list_helm_clusters() {
  find "${ROOT}/devops/clusters" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
}

usage() {
  cat <<'EOF'
Uninstall Workbench Helm releases (main umbrella, then CRDs umbrella) from the target cluster.

Usage:
  ./scripts/helm-destroy.sh [options]

Options:
  --cluster <name>      Cluster overlay name (default: local)
  --context <name>      kubectl context (overrides cluster.conf)
  --skip-context-switch Do not change kubectl context before uninstall
  --wait                Wait for resources to be removed before returning
  --keep-history        Keep release history after uninstall
  -y, --auto-approve    Skip confirmation prompt
  -h, --help            Show this help

Environment:
  HELM_CLUSTER          Same as --cluster (default: local)
  HELM_RELEASE          Main release name (default: workbench-umbrella-<cluster>)
  HELM_CRDS_RELEASE     CRDs release name (default: workbench-crds-umbrella-<cluster>)
  HELM_CRDS_NAMESPACE   CRDs Helm release namespace (default: kube-system)
  HELM_NAMESPACE        Main release namespace (default: workbench-platform)
  KUBECTL_CONTEXT       Explicit kubectl context
  KIND_CLUSTER_NAME     kind cluster for --cluster local (default: workbench-0)
  AKS_RESOURCE_GROUP    AKS RG for --cluster aks (default: workbench)
  AKS_CLUSTER_NAME      AKS name for --cluster aks (default: workbench-aks)
  HELM_FETCH_AKS_CREDENTIALS  auto|false — run az aks get-credentials if context missing

Examples:
  ./scripts/helm-destroy.sh --cluster local
  ./scripts/helm-destroy.sh --cluster aks --wait -y
EOF
  echo ""
  echo "Available clusters:"
  list_helm_clusters | sed 's/^/  /'
}

require_helm() {
  if ! command -v helm >/dev/null 2>&1; then
    echo "helm is not installed or not on PATH." >&2
    exit 1
  fi
}

confirm_uninstall() {
  local release="$1"
  local namespace="$2"
  local reply
  read -r -p "Uninstall Helm release '${release}' in namespace '${namespace}'? [y/N] " reply
  reply="$(echo "${reply}" | tr '[:upper:]' '[:lower:]')"
  [[ "${reply}" == "y" || "${reply}" == "yes" ]]
}

extra_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --cluster" >&2
        exit 1
      fi
      HELM_CLUSTER="$2"
      shift 2
      ;;
    --context)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --context" >&2
        exit 1
      fi
      KUBECTL_CONTEXT="$2"
      shift 2
      ;;
    --skip-context-switch)
      HELM_SKIP_CONTEXT_SWITCH=1
      shift
      ;;
    --wait)
      HELM_WAIT=true
      shift
      ;;
    --keep-history)
      HELM_KEEP_HISTORY=true
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
      extra_args+=("$1")
      shift
      ;;
  esac
done

VALUES_CLUSTER="${ROOT}/devops/clusters/${HELM_CLUSTER}/global-values.yaml"
RELEASE="${HELM_RELEASE:-workbench-umbrella-${HELM_CLUSTER}}"
CRDS_RELEASE="${HELM_CRDS_RELEASE:-workbench-crds-umbrella-${HELM_CLUSTER}}"
NAMESPACE="${HELM_NAMESPACE}"

if [[ ! -f "${VALUES_CLUSTER}" ]]; then
  echo "Unknown cluster: ${HELM_CLUSTER}" >&2
  echo "Set --cluster or HELM_CLUSTER. Available:" >&2
  list_helm_clusters | sed 's/^/  /' >&2
  exit 1
fi

require_helm

if [[ "${HELM_SKIP_CONTEXT_SWITCH}" != "1" ]]; then
  # shellcheck source=scripts/lib/helm-kubectl-context.sh
  source "${ROOT}/scripts/lib/helm-kubectl-context.sh"
  helm_kubectl_use_context "${HELM_CLUSTER}"
fi

if ! helm status "${RELEASE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Release '${RELEASE}' not found in namespace '${NAMESPACE}' (cluster: ${HELM_CLUSTER})." >&2
  exit 1
fi

echo "==> helm status ${RELEASE} -n ${NAMESPACE}"
helm status "${RELEASE}" -n "${NAMESPACE}"

if [[ "${AUTO_APPROVE}" != "true" ]]; then
  if ! confirm_uninstall "${RELEASE}" "${NAMESPACE}"; then
    echo "Aborted."
    exit 0
  fi
fi

cmd=(helm uninstall "${RELEASE}" -n "${NAMESPACE}")
if [[ "${HELM_WAIT}" == "true" ]]; then
  cmd+=(--wait)
fi
if [[ "${HELM_KEEP_HISTORY}" == "true" ]]; then
  cmd+=(--keep-history)
fi
if ((${#extra_args[@]} > 0)); then
  cmd+=("${extra_args[@]}")
fi

echo "==> ${cmd[*]}"
"${cmd[@]}"

if helm status "${CRDS_RELEASE}" -n "${HELM_CRDS_NAMESPACE}" >/dev/null 2>&1; then
  crds_cmd=(helm uninstall "${CRDS_RELEASE}" -n "${HELM_CRDS_NAMESPACE}")
elif helm status "${CRDS_RELEASE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "CRDs release found in legacy namespace '${NAMESPACE}' (pre kube-system split)."
  crds_cmd=(helm uninstall "${CRDS_RELEASE}" -n "${NAMESPACE}")
  if [[ "${HELM_WAIT}" == "true" ]]; then
    crds_cmd+=(--wait)
  fi
  if [[ "${HELM_KEEP_HISTORY}" == "true" ]]; then
    crds_cmd+=(--keep-history)
  fi
  echo "==> ${crds_cmd[*]}"
  "${crds_cmd[@]}"
else
  echo "CRDs release '${CRDS_RELEASE}' not found in '${HELM_CRDS_NAMESPACE}' or '${NAMESPACE}' (skip)."
fi
