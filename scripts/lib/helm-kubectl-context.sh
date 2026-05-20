#!/bin/bash
# shellcheck shell=bash
# Select kubectl context for a Helm cluster overlay before helm upgrade.
#
# Sourced by helm-apply.sh unless --skip-context-switch / HELM_SKIP_CONTEXT_SWITCH=1.
#
# Per-cluster defaults live in devops/clusters/<cluster>/cluster.conf.
# Explicit --context / KUBECTL_CONTEXT wins over cluster.conf.

helm_kubectl_require_kubectl() {
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "helm-kubectl-context: kubectl is required to switch context." >&2
    exit 1
  fi
}

helm_kubectl_load_cluster_conf() {
  local cluster="$1"
  local conf="${ROOT}/devops/clusters/${cluster}/cluster.conf"
  if [[ -f "${conf}" ]]; then
    # shellcheck disable=SC1090
    source "${conf}"
  fi
}

helm_kubectl_context_name() {
  local cluster="$1"
  if [[ -n "${KUBECTL_CONTEXT:-}" ]]; then
    printf '%s' "${KUBECTL_CONTEXT}"
    return 0
  fi
  helm_kubectl_load_cluster_conf "${cluster}"
  if [[ -n "${KUBECTL_CONTEXT:-}" ]]; then
    printf '%s' "${KUBECTL_CONTEXT}"
    return 0
  fi
  echo "helm-kubectl-context: no kubectl context for cluster '${cluster}'." >&2
  echo "Set --context, KUBECTL_CONTEXT, or devops/clusters/${cluster}/cluster.conf" >&2
  return 1
}

helm_kubectl_context_exists() {
  local ctx="$1"
  kubectl config get-contexts -o name 2>/dev/null | grep -Fxq "${ctx}"
}

helm_kubectl_fetch_aks_credentials() {
  if ! command -v az >/dev/null 2>&1; then
    echo "helm-kubectl-context: az CLI is required to fetch AKS credentials." >&2
    exit 1
  fi
  helm_kubectl_load_cluster_conf "aks"
  local rg="${AKS_RESOURCE_GROUP:-workbench}"
  local name="${AKS_CLUSTER_NAME:-workbench-aks}"
  echo "==> az aks get-credentials --resource-group ${rg} --name ${name}" >&2
  az aks get-credentials --resource-group "${rg}" --name "${name}" --overwrite-existing
}

# Usage: helm_kubectl_use_context <cluster>
helm_kubectl_use_context() {
  local cluster="$1"
  local ctx

  helm_kubectl_require_kubectl
  ctx="$(helm_kubectl_context_name "${cluster}")"

  if [[ "${cluster}" == "aks" && "${HELM_FETCH_AKS_CREDENTIALS:-auto}" != "false" ]]; then
    if ! helm_kubectl_context_exists "${ctx}"; then
      helm_kubectl_fetch_aks_credentials
    fi
  fi

  if ! helm_kubectl_context_exists "${ctx}"; then
    echo "kubectl context '${ctx}' not found." >&2
    case "${cluster}" in
      local)
        echo "Create kind first, e.g.: ./scripts/kind-wizard.sh create --name ${KIND_CLUSTER_NAME:-workbench-0}" >&2
        echo "Then: kubectl config use-context kind-${KIND_CLUSTER_NAME:-workbench-0}" >&2
        ;;
      aks)
        echo "Fetch credentials, e.g.: az aks get-credentials --resource-group ${AKS_RESOURCE_GROUP:-workbench} --name ${AKS_CLUSTER_NAME:-workbench-aks}" >&2
        ;;
    esac
    exit 1
  fi

  local current
  current="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "${current}" == "${ctx}" ]]; then
    echo "==> kubectl context already set: ${ctx}" >&2
    return 0
  fi

  echo "==> kubectl config use-context ${ctx}" >&2
  kubectl config use-context "${ctx}" >/dev/null
}
