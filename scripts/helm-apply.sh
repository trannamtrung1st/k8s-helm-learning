#!/bin/bash
set -euo pipefail

# Install the Workbench stack Helm release (main umbrella only).
# Run from repository root. Requires helm and kubectl context.
#
#   ./scripts/helm-apply.sh
#   ./scripts/helm-apply.sh --cluster local
#   ./scripts/helm-apply.sh --cluster aks --dry-run
#   ./scripts/helm-apply.sh --dry-run=server
#
# Cluster platform prerequisites (install separately — see kind-e2e-first-run.sh):
#   ./scripts/istio-helm-install.sh, ./scripts/rabbitmq-install.sh
# Helm release: workbench-umbrella-<cluster> — devops/workbench-umbrella (namespace workbench-platform)
#
# AKS: credentials in devops/clusters/aks/global-values.yaml are placeholders (CHANGEME).
# helm-apply reads matching secrets from Azure Key Vault (terraform output key_vault_name) and merges
# them as a final -f overlay. Requires az + jq and Key Vault Secrets User (or Officer).
#   KEY_VAULT_NAME=my-kv ./scripts/helm-apply.sh --cluster aks
#   ./scripts/helm-apply.sh --cluster aks --skip-kv-secrets   # file values only (lint/dev)
#
# Switches kubectl context from devops/clusters/<cluster>/cluster.conf before apply.
#   ./scripts/helm-apply.sh --cluster local    # kind-workbench-0 (default)
#   ./scripts/helm-apply.sh --cluster aks      # workbench-aks (fetches creds if missing)
#   ./scripts/helm-apply.sh --context my-ctx --cluster aks
#   ./scripts/helm-apply.sh --skip-context-switch
#
# After a failed/pending upgrade: ./scripts/helm-recover.sh then re-run this script.
#
# Server-side apply uses --force-conflicts (override field manager conflicts). Pass --no-force-conflicts to skip.
#
# Environment:
#   HELM_NAMESPACE          Main stack release namespace (default: workbench-platform)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${ROOT}/devops/workbench-umbrella"
HELM_CLUSTER="${HELM_CLUSTER:-local}"
HELM_RELEASE="${HELM_RELEASE:-}"
HELM_NAMESPACE="${HELM_NAMESPACE:-workbench-platform}"
HISTORY_MAX="${HELM_HISTORY_MAX:-5}"
HELM_SKIP_KV_SECRETS="${HELM_SKIP_KV_SECRETS:-0}"
HELM_SKIP_CONTEXT_SWITCH="${HELM_SKIP_CONTEXT_SWITCH:-0}"
HELM_FORCE_CONFLICTS="${HELM_FORCE_CONFLICTS:-1}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"
KV_VALUES_FILE=""

cleanup() {
  if [[ -n "${KV_VALUES_FILE}" && -f "${KV_VALUES_FILE}" ]]; then
    rm -f "${KV_VALUES_FILE}"
  fi
}
trap cleanup EXIT

list_helm_clusters() {
  find "${ROOT}/devops/clusters" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
}

usage() {
  sed -n '4,15p' "$0" | sed 's/^# \{0,1\}//'
  echo ""
  echo "Options:"
  echo "  --cluster <name>      Values overlay under devops/clusters/<name>/ (default: local)"
  echo "  --context <name>      kubectl context (overrides cluster.conf; default from cluster)"
  echo "  --skip-context-switch Do not change kubectl context before apply"
  echo "  --skip-kv-secrets     Skip Azure Key Vault overlay (AKS only; uses file values as-is)"
  echo "  --dry-run             Server-side dry-run (same as --dry-run=server)"
  echo "  --force               Server-side apply with --force-conflicts (default)"
  echo "  --no-force-conflicts  Do not pass --force-conflicts to helm upgrade"
  echo "  -h, --help            Show this help"
  echo ""
  echo "AKS Key Vault (when --cluster aks and not --skip-kv-secrets):"
  echo "  KEY_VAULT_NAME        Vault name (from terraform output key_vault_name)"
  echo ""
  echo "Context (see devops/clusters/<cluster>/cluster.conf):"
  echo "  KUBECTL_CONTEXT       Explicit kubectl context"
  echo "  KIND_CLUSTER_NAME     kind cluster for --cluster local (default: workbench-0)"
  echo "  AKS_RESOURCE_GROUP    AKS RG for --cluster aks (default: workbench)"
  echo "  AKS_CLUSTER_NAME      AKS name for --cluster aks (default: workbench-aks)"
  echo "  HELM_FETCH_AKS_CREDENTIALS  auto|false — run az aks get-credentials if context missing"
  echo ""
  echo "Available clusters:"
  list_helm_clusters | sed 's/^/  /'
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
    --skip-kv-secrets)
      HELM_SKIP_KV_SECRETS=1
      shift
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
    --dry-run)
      extra_args+=(--dry-run=server)
      shift
      ;;
    --force)
      HELM_FORCE_CONFLICTS=1
      shift
      ;;
    --no-force-conflicts)
      HELM_FORCE_CONFLICTS=0
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

# shellcheck source=scripts/lib/terraform-outputs.sh
source "${ROOT}/scripts/lib/terraform-outputs.sh"
terraform_outputs_apply_env

VALUES_PLATFORM="${ROOT}/devops/platform/values/global-values.yaml"
VALUES_CLUSTER="${ROOT}/devops/clusters/${HELM_CLUSTER}/global-values.yaml"
VALUES_LOCAL_CA="${ROOT}/devops/clusters/${HELM_CLUSTER}/local-ca.values.yaml"
RELEASE="${HELM_RELEASE:-workbench-umbrella-${HELM_CLUSTER}}"
NAMESPACE="${HELM_NAMESPACE}"

if [[ ! -f "${VALUES_CLUSTER}" ]]; then
  echo "Missing cluster values: ${VALUES_CLUSTER}" >&2
  echo "Set --cluster or HELM_CLUSTER. Available:" >&2
  list_helm_clusters | sed 's/^/  /' >&2
  exit 1
fi

if [[ "${HELM_CLUSTER}" == "aks" && "${HELM_SKIP_KV_SECRETS}" != "1" ]]; then
  # shellcheck source=scripts/lib/helm-kv-values.sh
  source "${ROOT}/scripts/lib/helm-kv-values.sh"
  KV_VALUES_FILE="$(mktemp "${TMPDIR:-/tmp}/workbench-kv-values.XXXXXX")"
  helm_kv_values_write "${KV_VALUES_FILE}"
fi

"${ROOT}/scripts/helm-dependency-update.sh"

if [[ "${HELM_SKIP_CONTEXT_SWITCH}" != "1" ]]; then
  # shellcheck source=scripts/lib/helm-kubectl-context.sh
  source "${ROOT}/scripts/lib/helm-kubectl-context.sh"
  helm_kubectl_use_context "${HELM_CLUSTER}"
fi

helm_upgrade_base() {
  local release="$1"
  local chart="$2"
  local release_namespace="$3"
  local create_namespace="$4"
  shift 4
  local -a cmd
  cmd=(
    helm upgrade "${release}" "${chart}"
    --server-side=true
    --install
    -n "${release_namespace}"
    --history-max "${HISTORY_MAX}"
  )
  if [[ "${create_namespace}" == "1" ]]; then
    cmd+=(--create-namespace)
  fi
  if [[ "${HELM_FORCE_CONFLICTS}" == "1" ]]; then
    cmd+=(--force-conflicts)
  fi
  if ((${#extra_args[@]} > 0)); then
    cmd+=("${extra_args[@]}")
  fi
  if ((${#@} > 0)); then
    cmd+=("$@")
  fi
  echo "==> ${cmd[*]}"
  "${cmd[@]}"
}

main_extra=(-f "${VALUES_PLATFORM}" -f "${VALUES_CLUSTER}")
if [[ -f "${VALUES_LOCAL_CA}" ]]; then
  main_extra+=(-f "${VALUES_LOCAL_CA}")
fi
if [[ -n "${KV_VALUES_FILE}" ]]; then
  main_extra+=(-f "${KV_VALUES_FILE}")
fi

echo "==> Workbench stack release: ${RELEASE} (namespace ${NAMESPACE})"
helm_upgrade_base "${RELEASE}" "${CHART}" "${NAMESPACE}" 1 "${main_extra[@]}"
