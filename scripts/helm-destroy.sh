#!/bin/bash
set -euo pipefail

# Uninstall the Workbench application stack (main umbrella only by default).
# Run from repository root. Requires helm and kubectl context.
#
# Default: remove workbench-umbrella-<cluster> only so cluster platform layers stay
# installed (Istio ambient, Gateway API CRDs, RabbitMQ Cluster Operator). Re-apply
# with ./scripts/helm-apply.sh without recreating the cluster.
#
#   ./scripts/helm-destroy.sh
#   ./scripts/helm-destroy.sh --cluster local -y
#   ./scripts/helm-destroy.sh --cluster aks --with-operator -y   # also remove RabbitMQ operator
#
# Switches kubectl context from devops/clusters/<cluster>/cluster.conf before uninstall
# (same as helm-apply.sh). Override release or namespace:
#   HELM_RELEASE=workbench-umbrella-aks ./scripts/helm-destroy.sh --cluster aks
#   HELM_NAMESPACE=workbench-platform ./scripts/helm-destroy.sh --cluster local

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM_CLUSTER="${HELM_CLUSTER:-local}"
HELM_RELEASE="${HELM_RELEASE:-}"
HELM_NAMESPACE="${HELM_NAMESPACE:-workbench-platform}"
HELM_SKIP_CONTEXT_SWITCH="${HELM_SKIP_CONTEXT_SWITCH:-0}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"
AUTO_APPROVE=false
HELM_WAIT=false
HELM_KEEP_HISTORY=false
UNINSTALL_OPERATOR=false

list_helm_clusters() {
  find "${ROOT}/devops/clusters" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
}

usage() {
  cat <<'EOF'
Uninstall Workbench Helm releases from the target cluster.

By default removes only workbench-umbrella-<cluster> (apps, infra, platform subcharts
in the umbrella). Keeps cluster platform installs so you can helm-apply again without
recreating the cluster:

  Preserved (default destroy):
    - Istio ambient (istio-base, istiod, istio-cni, ztunnel in istio-system)
    - Kubernetes Gateway API CRDs
    - RabbitMQ Cluster Operator (rabbitmq-system)
    - (gateway and HTTPRoutes ship in workbench-umbrella and are removed with it)

  Removed (default destroy):
    - workbench-umbrella-<cluster> (workbench-apps, workbench-infra, workbench-db, …)

Use --with-operator to also remove the RabbitMQ Cluster Operator via
./scripts/rabbitmq-install.sh --uninstall. Cluster-scoped CRD objects may remain until
deleted manually.

Usage:
  ./scripts/helm-destroy.sh [options]

Options:
  --cluster <name>      Cluster overlay name (default: local)
  --context <name>      kubectl context (overrides cluster.conf)
  --skip-context-switch Do not change kubectl context before uninstall
  --with-operator       Also uninstall RabbitMQ Cluster Operator
  --wait                Wait for resources to be removed before returning
  --keep-history        Keep release history after uninstall
  -y, --auto-approve    Skip confirmation prompt
  -h, --help            Show this help

Environment:
  HELM_CLUSTER          Same as --cluster (default: local)
  HELM_RELEASE          Main release name (default: workbench-umbrella-<cluster>)
  HELM_NAMESPACE        Main release namespace (default: workbench-platform)
  KUBECTL_CONTEXT       Explicit kubectl context
  KIND_CLUSTER_NAME     kind cluster for --cluster local (default: workbench-0)
  AKS_RESOURCE_GROUP    AKS RG for --cluster aks (default: workbench)
  AKS_CLUSTER_NAME      AKS name for --cluster aks (default: workbench-aks)
  HELM_FETCH_AKS_CREDENTIALS  auto|false — run az aks get-credentials if context missing

Examples:
  ./scripts/helm-destroy.sh --cluster local
  ./scripts/helm-destroy.sh --cluster local -y
  ./scripts/helm-destroy.sh --cluster aks --with-operator --wait -y
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

helm_uninstall_release() {
  local release="$1"
  local namespace="$2"
  local -a cmd
  cmd=(helm uninstall "${release}" -n "${namespace}")
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
    --with-operator)
      UNINSTALL_OPERATOR=true
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

uninstalled_any=false

if helm status "${RELEASE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "==> helm status ${RELEASE} -n ${NAMESPACE}"
  helm status "${RELEASE}" -n "${NAMESPACE}"

  if [[ "${AUTO_APPROVE}" != "true" ]]; then
    if ! confirm_uninstall "${RELEASE}" "${NAMESPACE}"; then
      echo "Aborted."
      exit 0
    fi
  fi

  helm_uninstall_release "${RELEASE}" "${NAMESPACE}"
  uninstalled_any=true
else
  echo "Release '${RELEASE}' not found in namespace '${NAMESPACE}' (skip main umbrella)."
fi

if [[ "${UNINSTALL_OPERATOR}" == "true" ]]; then
  echo "==> RabbitMQ Cluster Operator uninstall"
  rmq_uninstall_args=(--uninstall)
  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    rmq_uninstall_args+=(-y)
  fi
  "${ROOT}/scripts/rabbitmq-install.sh" "${rmq_uninstall_args[@]}"
  uninstalled_any=true
else
  echo "Keeping RabbitMQ Cluster Operator (pass --with-operator to uninstall)."
  echo "Keeping Istio / Gateway API CRDs (not managed by this script)."
fi

if [[ "${uninstalled_any}" != "true" ]]; then
  echo "Nothing to uninstall."
fi

echo "Done. Re-apply stack: ./scripts/helm-apply.sh --cluster ${HELM_CLUSTER}"
